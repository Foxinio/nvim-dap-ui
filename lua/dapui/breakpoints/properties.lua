--- Registry of breakpoint properties and how their values are read.
local M = {}

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

--- nvim-dap breakpoint field → argument name of `dap.breakpoints.toggle`.
M.virtual_args =
  { condition = "condition", hitCondition = "hit_condition", logMessage = "log_message" }

---@type dapui.breakpoints.Property[]
local properties = {}
---@type table<string, dapui.breakpoints.Property>
local by_name = {}

function M.non_empty(value)
  return value ~= nil and value ~= ""
end

function M.is_default(property, value)
  if value == nil then
    return true
  end
  return vim.deep_equal(value, property.default)
end

--- Add or replace a property. Returns the stored definition.
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
  return property
end

---@return dapui.breakpoints.Property[]
function M.all()
  return properties
end

---@return dapui.breakpoints.Property?
function M.get(name)
  return by_name[name]
end

--- Value of a property for a breakpoint: virtual ones from nvim-dap, others
--- from the record, falling back to the default.
---@param bp dapui.breakpoints.Breakpoint
---@param record? table
function M.value(bp, record, property)
  if property.virtual then
    local value = bp[property.virtual]
    return M.non_empty(value) and value or property.default
  end
  local value = record and record.props[property.name]
  if value == nil then
    return property.default
  end
  return value
end

--- All property values of a breakpoint, by name.
function M.values(bp, record)
  local values = {}
  for _, property in ipairs(properties) do
    values[property.name] = M.value(bp, record, property)
  end
  return values
end

return M
