---@toc_entry Breakpoint properties
---@text
--- Extra properties for nvim-dap breakpoints, and control over which
--- breakpoints are sent to the debug adapter.
---
--- nvim-dap stays the only owner of the breakpoint list, of each breakpoint's
--- position and of `condition`, `hitCondition` and `logMessage`. This module
--- only stores properties nvim-dap has no field for. A breakpoint gets a record
--- here only while one of those properties differs from its default.
---
--- Other plugins can register their own properties with `register` (they are
--- shown and edited in the Breakpoints element) and hold breakpoints back from
--- the adapter with `add_rule`. A breakpoint that is held back or disabled stays
--- in nvim-dap's list, keeping its condition and log message; it is just not
--- sent.
---
--- The module only needs nvim-dap. It does not load the rest of nvim-dap-ui.
---
--- Submodules: `properties` (registry and values), `records` (stored
--- properties and handles), `rules` (active check), `signs`, `send` (session
--- wrapper and refresh).
---@class dapui.breakpoints
local M = {}

local properties = require("dapui.breakpoints.properties")
local records = require("dapui.breakpoints.records")
local rules = require("dapui.breakpoints.rules")
local signs = require("dapui.breakpoints.signs")
local send = require("dapui.breakpoints.send")

--- Sign shown on breakpoints that are disabled or held back by a rule. Change
--- its `text` and `highlight` fields to restyle it.
M.inactive_sign = signs.inactive

-- `_backend` (nvim-dap's breakpoints, replaceable for tests) lives in records.
setmetatable(M, {
  __index = function(_, key)
    if key == "_backend" then
      return records.backend
    end
  end,
  __newindex = function(t, key, value)
    if key == "_backend" then
      records.backend = value
    else
      rawset(t, key, value)
    end
  end,
})

--- Register a property shown and edited in the Breakpoints element.
--- Registering a name again replaces the earlier definition.
---@param name string
---@param spec table See |dapui.breakpoints.Property|
function M.register(name, spec)
  properties.register(name, spec)
  send.changed()
end

--- Registered properties, in display order.
---@return dapui.breakpoints.Property[]
function M.properties()
  local all = properties.all()
  return vim.list_slice(all, 1, #all)
end

--- Hold breakpoints back from the debug adapter: a breakpoint is sent only if
--- every rule returns true for it. Adding a name again replaces the rule.
---@param name string
---@param rule fun(bp: dapui.breakpoints.Breakpoint): boolean
function M.add_rule(name, rule)
  rules.add(name, rule)
end

---@param name string
function M.remove_rule(name)
  rules.remove(name)
end

--- The nvim-dap breakpoint at a location, or nil.
---@return dapui.breakpoints.Breakpoint?
function M.breakpoint(bufnr, line)
  return records.breakpoints(bufnr)[line]
end

--- Property values of a breakpoint (all of them, or one by name). Unset
--- properties return their defaults. Returns nil if there is no breakpoint.
---@param bufnr integer
---@param line integer
---@param name? string
function M.get(bufnr, line, name)
  records.prune(bufnr)
  local bp = records.breakpoints(bufnr)[line]
  if not bp then
    return nil
  end
  local _, record = records.find(bufnr, line)
  if name then
    local property = assert(properties.get(name), "Unknown breakpoint property: " .. name)
    return properties.value(bp, record, property)
  end
  return properties.values(bp, record)
end

--- Whether a breakpoint is sent to the debug adapter.
---@return boolean
function M.is_active(bufnr, line)
  local bp = records.breakpoints(bufnr)[line]
  if not bp then
    return false
  end
  local _, record = records.find(bufnr, line)
  return rules.active(bp, record)
end

--- Send breakpoints to every debug session again, after a property or rule
--- result changed. Without `bufnr`, all buffers with breakpoints are sent.
---@param bufnr? integer
function M.refresh(bufnr)
  send.refresh(bufnr)
end

--- Set a property. Setting the default (or nil) removes it. Properties nvim-dap
--- owns (condition, hit_condition, log_message) are written to nvim-dap.
---@param bufnr integer
---@param line integer
---@param name string
---@param value any
---@return boolean set False if there is no breakpoint at the location
function M.set(bufnr, line, name, value)
  local property = assert(properties.get(name), "Unknown breakpoint property: " .. name)
  records.prune(bufnr)
  local bp = records.breakpoints(bufnr)[line]
  if not bp then
    return false
  end
  if property.virtual then
    local args = {}
    for field, arg in pairs(properties.virtual_args) do
      args[arg] = bp[field]
    end
    args[properties.virtual_args[property.virtual]] = properties.non_empty(value) and value or nil
    records.backend.remove(bufnr, line)
    records.backend.toggle(args, bufnr, line)
  else
    local mark, record = records.ensure(bufnr, line)
    if properties.is_default(property, value) then
      record.props[name] = nil
    else
      record.props[name] = value
    end
    records.drop_if_default(bufnr, mark, record)
  end
  send.refresh(bufnr)
  return true
end

--- Remove a breakpoint from nvim-dap together with its properties.
function M.remove(bufnr, line)
  local mark, record = records.find(bufnr, line)
  if record then
    records.delete(bufnr, mark)
  end
  records.backend.remove(bufnr, line)
  send.refresh(bufnr)
end

--- A stable handle for a breakpoint that follows it through edits, for
--- properties that refer to other breakpoints. Release it when no longer used.
---@return integer? handle Nil if there is no breakpoint at the location
function M.handle(bufnr, line)
  return records.handle(bufnr, line)
end

--- Location of a handle's breakpoint, or nil once the breakpoint is gone.
---@return integer? bufnr, integer? line
function M.locate(handle)
  return records.locate(handle)
end

function M.release(handle)
  records.release(handle)
end

--- Every nvim-dap breakpoint with its properties, grouped by buffer and sorted
--- by line. Each entry has `buf`, `line`, `active`, `breakpoint` (nvim-dap's
--- entry) and `properties` (name → value).
---@return { buffer: integer, name: string, breakpoints: table[] }[]
function M.list()
  local result = {}
  for bufnr, buf_bps in pairs(records.backend.get()) do
    records.prune(bufnr)
    local entries = {}
    for _, bp in ipairs(buf_bps) do
      bp.buf = bp.buf or bufnr
      local _, record = records.find(bufnr, bp.line)
      entries[#entries + 1] = {
        buf = bufnr,
        line = bp.line,
        active = rules.active(bp, record),
        breakpoint = bp,
        properties = properties.values(bp, record),
      }
    end
    table.sort(entries, function(a, b)
      return a.line < b.line
    end)
    result[#result + 1] =
      { buffer = bufnr, name = vim.api.nvim_buf_get_name(bufnr), breakpoints = entries }
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

M.register("enabled", { label = "Enabled", type = "boolean", default = true })
M.register("condition", { label = "Condition", type = "string", virtual = "condition" })
M.register("hit_condition", { label = "Hit Condition", type = "string", virtual = "hitCondition" })
M.register("log_message", { label = "Log Message", type = "string", virtual = "logMessage" })
send.install()

return M
