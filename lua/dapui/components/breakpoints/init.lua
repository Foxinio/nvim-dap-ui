local config = require("dapui.config")
local nio = require("nio")
local util = require("dapui.util")
local store = require("dapui.breakpoints")
local values = require("dapui.components.breakpoints.properties")

---@param client dapui.DAPClient
return function(client, send_ready)
  ---@type table<string, boolean>
  local expanded = {}

  for _, event in ipairs({
    "setBreakpoints",
    "setFunctionBreakpoints",
    "setInstructionBreakpoints",
    "setDataBreakpoints",
    "breakpoint",
    "stackTrace",
    "terminated",
    "exited",
    "disconnect",
  }) do
    client.listen[event](send_ready)
  end
  -- One Breakpoints element at a time: a new one replaces the old redraw hook.
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("dapui_breakpoints_element", { clear = true }),
    pattern = "DapUIBreakpointsChanged",
    callback = function()
      -- send_ready() renders right away inside the caller, which may hold
      -- textlock (completion, expression mappings, statusline). Redraw from
      -- the main loop instead.
      vim.schedule(send_ready)
    end,
  })

  return {
    ---@param canvas dapui.Canvas
    render = function(canvas)
      local current_frame = client.session and client.session.current_frame
      local current_line = 0
      local current_file = ""
      if current_frame and current_frame.source and current_frame.source.path then
        current_file = nio.fn.bufname(current_frame.source.path)
        current_line = current_frame.line
      end
      local indent = config.render.indent
      local properties = store.properties()
      for _, data in ipairs(store.list()) do
        local buffer, bufname = data.buffer, data.name
        local name = util.pretty_name(bufname)
        canvas:write(name, { group = "DapUIBreakpointsPath" })
        canvas:write(":\n")

        for _, entry in ipairs(data.breakpoints) do
          local bp = entry.breakpoint
          local text = vim.api.nvim_buf_get_lines(buffer, bp.line - 1, bp.line, false)
          local key = buffer .. ":" .. bp.line
          local jump_to_bp = util.partial(
            client.lib.jump_to_frame,
            { line = bp.line, column = 0, source = { path = bufname } }
          )
          local function collapse()
            expanded[key] = nil
            send_ready()
          end
          local function add_bp_mappings()
            canvas:add_mapping("open", jump_to_bp)
            canvas:add_mapping("remove", function()
              store.remove(buffer, bp.line)
            end)
            canvas:add_mapping("toggle", function()
              store.set(buffer, bp.line, "enabled", not entry.properties.enabled)
            end)
            canvas:add_mapping("expand", function()
              expanded[key] = not expanded[key] or nil
              send_ready()
            end)
            -- Editing starts by showing the breakpoint's properties.
            canvas:add_mapping("edit", function()
              if not expanded[key] then
                expanded[key] = true
                send_ready()
              end
            end)
            if expanded[key] then
              canvas:add_mapping("collapse", collapse)
            end
          end
          if vim.tbl_count(text) ~= 0 then
            add_bp_mappings()
            canvas:write(string.rep(" ", indent))
            local group
            if not entry.active then
              group = "DapUIBreakpointsDisabledLine"
            elseif bp.line == current_line and name == current_file then
              group = "DapUIBreakpointsCurrentLine"
            else
              group = "DapUIBreakpointsLine"
            end
            canvas:write(tostring(bp.line), { group = group })
            canvas:write(" " .. vim.trim(text[1]) .. "\n")

            local info_indent = indent + #tostring(bp.line) + 1
            local whitespace = string.rep(" ", info_indent)

            local function add_info(message, data)
              add_bp_mappings()
              canvas:write(whitespace)
              canvas:write(message, { group = "DapUIBreakpointsInfo" })
              canvas:write(" " .. data .. "\n")
            end

            if expanded[key] then
              for _, property in ipairs(properties) do
                local value = entry.properties[property.name]
                canvas:add_mapping("open", jump_to_bp)
                canvas:add_mapping("expand", collapse)
                canvas:add_mapping("collapse", collapse)
                canvas:add_mapping("edit", function()
                  values.edit(bp, property, value)
                end)
                canvas:write(whitespace)
                canvas:write(property.label .. ":", { group = "DapUIBreakpointsInfo" })
                canvas:write(" " .. values.format(property, value, bp) .. "\n")
              end
            else
              if bp.logMessage then
                add_info("Log Message:", bp.logMessage)
              end
              if bp.condition then
                add_info("Condition:", bp.condition)
              end
              if bp.hitCondition then
                add_info("Hit Condition:", bp.hitCondition)
              end
              for _, property in ipairs(properties) do
                local value = entry.properties[property.name]
                if
                  not property.virtual
                  and property.name ~= "enabled"
                  and not vim.deep_equal(value, property.default)
                then
                  local summary
                  if property.summary then
                    summary = property.summary(value, bp)
                  else
                    summary = property.label .. ": " .. values.format(property, value, bp)
                  end
                  if summary then
                    local label, rest = summary:match("^([^:]+:)%s*(.*)$")
                    if label then
                      add_info(label, rest)
                    else
                      add_bp_mappings()
                      canvas:write(whitespace .. summary .. "\n")
                    end
                  end
                end
              end
            end
          end
        end
        canvas:write("\n")
      end
      if canvas:length() > 1 then
        canvas:remove_line()
        canvas:remove_line()
      else
        canvas:write("")
      end
    end,
  }
end
