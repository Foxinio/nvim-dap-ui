--- Showing and editing breakpoint property values in the Breakpoints element.
local M = {}

local store = require("dapui.breakpoints")

--- Text for a property value.
function M.format(property, value, bp)
  if property.format then
    return property.format(value, bp)
  end
  if value == nil or value == "" then
    return "(none)"
  end
  if type(value) == "table" then
    return vim.inspect(value)
  end
  return tostring(value)
end

--- Change a property: prompt for text, flip booleans, or call `spec.edit`.
function M.edit(bp, property, current)
  local function set(value)
    store.set(bp.buf, bp.line, property.name, value)
  end
  if property.type == "boolean" then
    set(not current)
  elseif property.type == "custom" then
    if property.edit then
      property.edit(bp, current, set)
    end
  else
    vim.ui.input({
      prompt = property.label .. ": ",
      default = current ~= nil and tostring(current) or "",
    }, function(input)
      if input == nil then
        return
      end
      if property.type == "integer" then
        if input == "" then
          return set(nil)
        end
        local number = tonumber(input)
        if not number or number % 1 ~= 0 then
          vim.notify("Expected a whole number for " .. property.label, vim.log.levels.WARN)
          return
        end
        return set(number)
      end
      set(input ~= "" and input or nil)
    end)
  end
end

return M
