--- Which breakpoints are sent to the debug adapter: enabled ones that every
--- registered rule accepts.
local M = {}

local properties = require("dapui.breakpoints.properties")

---@type table<string, fun(bp: dapui.breakpoints.Breakpoint): boolean>
local rules = {}
local order = {}

function M.add(name, rule)
  if not rules[name] then
    order[#order + 1] = name
  end
  rules[name] = rule
end

function M.remove(name)
  rules[name] = nil
  order = vim.tbl_filter(function(rule)
    return rule ~= name
  end, order)
end

---@param bp dapui.breakpoints.Breakpoint
---@param record? table
---@return boolean
function M.active(bp, record)
  if properties.value(bp, record, properties.get("enabled")) == false then
    return false
  end
  for _, name in ipairs(order) do
    local ok, result = pcall(rules[name], bp)
    if not ok then
      vim.notify(("Breakpoint rule %s failed: %s"):format(name, result), vim.log.levels.ERROR)
    elseif result == false then
      return false
    end
  end
  return true
end

return M
