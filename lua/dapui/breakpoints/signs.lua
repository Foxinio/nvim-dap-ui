--- Signs on breakpoints with records: inactive, or a property's own sign.
local M = {}

local api = vim.api
local properties = require("dapui.breakpoints.properties")
local records = require("dapui.breakpoints.records")
local rules = require("dapui.breakpoints.rules")

--- Sign shown on breakpoints that are disabled or held back by a rule.
M.inactive = { text = "○", highlight = "DapBreakpointInactive" }

local function sign_for(bp, record)
  if not rules.active(bp, record) then
    return { M.inactive.text, M.inactive.highlight }
  end
  for _, property in ipairs(properties.all()) do
    if property.sign then
      local value = properties.value(bp, record, property)
      local sign = not properties.is_default(property, value) and property.sign(value, bp) or nil
      if sign then
        return sign
      end
    end
  end
end

function M.update(bufnr)
  local placed = records.placed(bufnr)
  if #placed == 0 then
    return
  end
  local bps = records.breakpoints(bufnr)
  for _, item in ipairs(placed) do
    local bp = bps[item.line]
    if bp then
      local sign = sign_for(bp, item.record)
      api.nvim_buf_set_extmark(bufnr, records.ns, item.line - 1, 0, {
        id = item.mark,
        sign_text = sign and sign[1] or nil,
        sign_hl_group = sign and sign[2] or nil,
        priority = 22,
      })
    end
  end
end

api.nvim_set_hl(0, "DapBreakpointInactive", { default = true, link = "Comment" })

return M
