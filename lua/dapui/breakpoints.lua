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
---@class dapui.breakpoints
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("dapui_breakpoint_properties")

---@class dapui.breakpoints.Breakpoint
---@field buf integer
---@field line integer
---@field condition? string
---@field hitCondition? string
---@field logMessage? string
---@field state? table

---@class dapui.breakpoints.Property
---@field name string
---@field label string Text shown in the Breakpoints element
---@field type "string"|"boolean"|"integer"|"custom"
---@field default any Value of a breakpoint that has not set the property
---@field edit? fun(bp: dapui.breakpoints.Breakpoint, current: any, set: fun(value: any)) Editor for `custom` properties
---@field format? fun(value: any, bp: dapui.breakpoints.Breakpoint): string Text for a value
---@field summary? fun(value: any, bp: dapui.breakpoints.Breakpoint): string? Line shown under a collapsed breakpoint when the value is not the default
---@field sign? fun(value: any, bp: dapui.breakpoints.Breakpoint): string[]? `{ text, highlight }` sign shown while the breakpoint is active
---@field virtual? string nvim-dap field the property reads and writes

--- Backend holding nvim-dap's breakpoints. Replaceable for tests.
M._backend = require("dap.breakpoints")

local virtual_args =
  { condition = "condition", hitCondition = "hit_condition", logMessage = "log_message" }

---@type dapui.breakpoints.Property[]
local properties = {}
---@type table<string, dapui.breakpoints.Property>
local by_name = {}
---@type table<string, fun(bp: dapui.breakpoints.Breakpoint): boolean>
local rules = {}
local rule_order = {}

--- buffer → extmark id → record
---@type table<integer, table<integer, { props: table<string, any>, anchors: integer }>>
local records = {}
--- handle → { buf, mark }
local handles = {}
local next_handle = 0

local function changed()
  api.nvim_exec_autocmds("User", { pattern = "DapUIBreakpointsChanged", modeline = false })
end

local function non_empty(value)
  return value ~= nil and value ~= ""
end

local function is_default(property, value)
  if value == nil then
    return true
  end
  return vim.deep_equal(value, property.default)
end

---@param bufnr integer
---@return table<integer, dapui.breakpoints.Breakpoint>
local function dap_breakpoints(bufnr)
  local result = {}
  if not api.nvim_buf_is_valid(bufnr) then
    return result
  end
  for _, bp in ipairs(M._backend.get(bufnr)[bufnr] or {}) do
    bp.buf = bp.buf or bufnr
    result[bp.line] = bp
  end
  return result
end

--- Drop records whose breakpoint is gone, and duplicates left on one line.
local function prune(bufnr)
  local buf_records = records[bufnr]
  if not buf_records then
    return
  end
  if not api.nvim_buf_is_valid(bufnr) then
    records[bufnr] = nil
    return
  end
  local bps = dap_breakpoints(bufnr)
  local seen = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    local id, line = mark[1], mark[2] + 1
    local record = buf_records[id]
    if record and (not bps[line] or seen[line]) then
      api.nvim_buf_del_extmark(bufnr, ns, id)
      buf_records[id] = nil
    elseif record then
      seen[line] = true
    end
  end
  -- Records whose extmark was removed with its text.
  for id in pairs(buf_records) do
    if not api.nvim_buf_get_extmark_by_id(bufnr, ns, id, {})[1] then
      buf_records[id] = nil
    end
  end
end

---@return integer? mark, table? record
local function find_record(bufnr, line)
  local buf_records = records[bufnr]
  if not buf_records then
    return
  end
  local marks = api.nvim_buf_get_extmarks(bufnr, ns, { line - 1, 0 }, { line - 1, -1 }, {})
  for _, mark in ipairs(marks) do
    if buf_records[mark[1]] then
      return mark[1], buf_records[mark[1]]
    end
  end
end

local function ensure_record(bufnr, line)
  local mark, record = find_record(bufnr, line)
  if record then
    return mark, record
  end
  mark = api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {})
  record = { props = {}, anchors = 0 }
  records[bufnr] = records[bufnr] or {}
  records[bufnr][mark] = record
  return mark, record
end

local function drop_if_default(bufnr, mark, record)
  if record.anchors > 0 or next(record.props) ~= nil then
    return
  end
  api.nvim_buf_del_extmark(bufnr, ns, mark)
  records[bufnr][mark] = nil
end

---@param bp dapui.breakpoints.Breakpoint
---@param record? table
local function property_value(bp, record, property)
  if property.virtual then
    local value = bp[property.virtual]
    return non_empty(value) and value or property.default
  end
  local value = record and record.props[property.name]
  if value == nil then
    return property.default
  end
  return value
end

local function active(bp, record)
  if property_value(bp, record, by_name.enabled) == false then
    return false
  end
  for _, name in ipairs(rule_order) do
    local ok, result = pcall(rules[name], bp)
    if not ok then
      vim.notify(("Breakpoint rule %s failed: %s"):format(name, result), vim.log.levels.ERROR)
    elseif result == false then
      return false
    end
  end
  return true
end

local function update_signs(bufnr)
  if not records[bufnr] or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  local bps = dap_breakpoints(bufnr)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    local record = records[bufnr][mark[1]]
    local bp = bps[mark[2] + 1]
    if record and bp then
      local sign
      if not active(bp, record) then
        sign = { M.inactive_sign.text, M.inactive_sign.highlight }
      else
        for _, property in ipairs(properties) do
          if property.sign then
            local value = property_value(bp, record, property)
            sign = not is_default(property, value) and property.sign(value, bp) or nil
            if sign then
              break
            end
          end
        end
      end
      api.nvim_buf_set_extmark(bufnr, ns, mark[2], 0, {
        id = mark[1],
        sign_text = sign and sign[1] or nil,
        sign_hl_group = sign and sign[2] or nil,
        priority = 22,
      })
    end
  end
end

--- Sign shown on breakpoints that are disabled or held back by a rule.
M.inactive_sign = { text = "○", highlight = "DapBreakpointInactive" }

--- Register a property shown and edited in the Breakpoints element.
--- Registering a name again replaces the earlier definition.
---@param name string
---@param spec table See |dapui.breakpoints.Property|
function M.register(name, spec)
  local property = vim.tbl_extend("force", { type = "string", label = name }, spec, { name = name })
  if by_name[name] then
    for index, existing in ipairs(properties) do
      if existing.name == name then
        properties[index] = property
      end
    end
  else
    properties[#properties + 1] = property
  end
  by_name[name] = property
  changed()
end

--- Registered properties, in display order.
---@return dapui.breakpoints.Property[]
function M.properties()
  return vim.list_slice(properties, 1, #properties)
end

--- Hold breakpoints back from the debug adapter: a breakpoint is sent only if
--- every rule returns true for it. Adding a name again replaces the rule.
---@param name string
---@param rule fun(bp: dapui.breakpoints.Breakpoint): boolean
function M.add_rule(name, rule)
  if not rules[name] then
    rule_order[#rule_order + 1] = name
  end
  rules[name] = rule
end

---@param name string
function M.remove_rule(name)
  rules[name] = nil
  rule_order = vim.tbl_filter(function(rule)
    return rule ~= name
  end, rule_order)
end

--- The nvim-dap breakpoint at a location, or nil.
---@return dapui.breakpoints.Breakpoint?
function M.breakpoint(bufnr, line)
  return dap_breakpoints(bufnr)[line]
end

--- Property values of a breakpoint (all of them, or one by name). Unset
--- properties return their defaults. Returns nil if there is no breakpoint.
---@param bufnr integer
---@param line integer
---@param name? string
function M.get(bufnr, line, name)
  prune(bufnr)
  local bp = dap_breakpoints(bufnr)[line]
  if not bp then
    return nil
  end
  local _, record = find_record(bufnr, line)
  if name then
    assert(by_name[name], "Unknown breakpoint property: " .. name)
    return property_value(bp, record, by_name[name])
  end
  local values = {}
  for _, property in ipairs(properties) do
    values[property.name] = property_value(bp, record, property)
  end
  return values
end

--- Whether a breakpoint is sent to the debug adapter.
---@return boolean
function M.is_active(bufnr, line)
  local bp = dap_breakpoints(bufnr)[line]
  if not bp then
    return false
  end
  local _, record = find_record(bufnr, line)
  return active(bp, record)
end

local function broadcast(sessions, fn)
  for _, session in pairs(sessions or {}) do
    fn(session)
    broadcast(session.children, fn)
  end
end

--- Send breakpoints to every debug session again, after a property or rule
--- result changed. Without `bufnr`, all buffers with breakpoints are sent.
---@param bufnr? integer
function M.refresh(bufnr)
  local bps = bufnr and M._backend.get(bufnr) or M._backend.get()
  if bufnr then
    bps[bufnr] = bps[bufnr] or {}
  end
  for buf in pairs(bps) do
    update_signs(buf)
  end
  local ok, dap = pcall(require, "dap")
  if ok and next(bps) then
    broadcast(dap.sessions(), function(session)
      session:set_breakpoints(bps)
    end)
  end
  changed()
end

--- Set a property. Setting the default (or nil) removes it. Properties nvim-dap
--- owns (condition, hit_condition, log_message) are written to nvim-dap.
---@param bufnr integer
---@param line integer
---@param name string
---@param value any
---@return boolean set False if there is no breakpoint at the location
function M.set(bufnr, line, name, value)
  local property = assert(by_name[name], "Unknown breakpoint property: " .. name)
  prune(bufnr)
  local bp = dap_breakpoints(bufnr)[line]
  if not bp then
    return false
  end
  if property.virtual then
    local args = {}
    for field, arg in pairs(virtual_args) do
      args[arg] = bp[field]
    end
    args[virtual_args[property.virtual]] = non_empty(value) and value or nil
    M._backend.remove(bufnr, line)
    M._backend.toggle(args, bufnr, line)
  else
    local mark, record = ensure_record(bufnr, line)
    if is_default(property, value) then
      record.props[name] = nil
    else
      record.props[name] = value
    end
    drop_if_default(bufnr, mark, record)
  end
  M.refresh(bufnr)
  return true
end

--- Remove a breakpoint from nvim-dap together with its properties.
function M.remove(bufnr, line)
  local mark, record = find_record(bufnr, line)
  if record then
    api.nvim_buf_del_extmark(bufnr, ns, mark)
    records[bufnr][mark] = nil
  end
  M._backend.remove(bufnr, line)
  M.refresh(bufnr)
end

--- A stable handle for a breakpoint that follows it through edits, for
--- properties that refer to other breakpoints. Release it when no longer used.
---@return integer? handle Nil if there is no breakpoint at the location
function M.handle(bufnr, line)
  prune(bufnr)
  if not dap_breakpoints(bufnr)[line] then
    return nil
  end
  local mark, record = ensure_record(bufnr, line)
  for handle, target in pairs(handles) do
    if target.buf == bufnr and target.mark == mark then
      return handle
    end
  end
  next_handle = next_handle + 1
  handles[next_handle] = { buf = bufnr, mark = mark }
  record.anchors = record.anchors + 1
  return next_handle
end

--- Location of a handle's breakpoint, or nil once the breakpoint is gone.
---@return integer? bufnr, integer? line
function M.locate(handle)
  local target = handles[handle]
  if not target then
    return
  end
  prune(target.buf)
  local record = records[target.buf] and records[target.buf][target.mark]
  if not record then
    handles[handle] = nil
    return
  end
  local position = api.nvim_buf_get_extmark_by_id(target.buf, ns, target.mark, {})
  return target.buf, position[1] + 1
end

function M.release(handle)
  local target = handles[handle]
  handles[handle] = nil
  if not target then
    return
  end
  local record = records[target.buf] and records[target.buf][target.mark]
  if record then
    record.anchors = record.anchors - 1
    drop_if_default(target.buf, target.mark, record)
  end
end

--- Every nvim-dap breakpoint with its properties, grouped by buffer and sorted
--- by line. Each entry has `buf`, `line`, `active`, `breakpoint` (nvim-dap's
--- entry) and `properties` (name → value).
---@return { buffer: integer, name: string, breakpoints: table[] }[]
function M.list()
  local result = {}
  for bufnr, buf_bps in pairs(M._backend.get()) do
    prune(bufnr)
    local entries = {}
    for _, bp in ipairs(buf_bps) do
      bp.buf = bp.buf or bufnr
      local _, record = find_record(bufnr, bp.line)
      local values = {}
      for _, property in ipairs(properties) do
        values[property.name] = property_value(bp, record, property)
      end
      entries[#entries + 1] = {
        buf = bufnr,
        line = bp.line,
        active = active(bp, record),
        breakpoint = bp,
        properties = values,
      }
    end
    table.sort(entries, function(a, b)
      return a.line < b.line
    end)
    result[#result + 1] =
      { buffer = bufnr, name = api.nvim_buf_get_name(bufnr), breakpoints = entries }
  end
  table.sort(result, function(a, b)
    return a.name < b.name
  end)
  return result
end

--- Hold back inactive breakpoints when a session sends them.
local function wrap(session)
  if rawget(session, "set_breakpoints") then
    return
  end
  local original = session.set_breakpoints
  session.set_breakpoints = function(self, bps, on_done)
    local filtered = {}
    for bufnr, buf_bps in pairs(bps) do
      prune(bufnr)
      filtered[bufnr] = vim.tbl_filter(function(bp)
        bp.buf = bp.buf or bufnr
        local _, record = find_record(bufnr, bp.line)
        return active(bp, record)
      end, buf_bps)
      update_signs(bufnr)
    end
    return original(self, filtered, on_done)
  end
end

M.register("enabled", { label = "Enabled", type = "boolean", default = true })
M.register("condition", { label = "Condition", type = "string", virtual = "condition" })
M.register("hit_condition", { label = "Hit Condition", type = "string", virtual = "hitCondition" })
M.register("log_message", { label = "Log Message", type = "string", virtual = "logMessage" })

local dap = require("dap")
dap.listeners.before.event_initialized["dapui.breakpoints"] = function(session)
  wrap(session)
end
broadcast(dap.sessions(), wrap)
api.nvim_set_hl(0, "DapBreakpointInactive", { default = true, link = "Comment" })
api.nvim_create_autocmd("BufWipeout", {
  group = api.nvim_create_augroup("dapui.breakpoints", { clear = true }),
  callback = function(args)
    records[args.buf] = nil
  end,
})

return M
