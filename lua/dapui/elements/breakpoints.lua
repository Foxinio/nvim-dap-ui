local config = require("dapui.config")
local Canvas = require("dapui.render.canvas")
local util = require("dapui.util")

---@param client dapui.DAPClient
---@nodoc
return function(client)
  local dapui = { elements = {} }

  ---@class dapui.elements.breakpoints
  ---@toc_entry Breakpoints
  ---@text
  --- Lists all breakpoints currently set.
  ---
  --- Mappings:
  --- - `open`: Jump to the location the breakpoint is set
  --- - `toggle`: Enable/disable the selected breakpoint. A disabled breakpoint
  ---   stays in nvim-dap's list but is not sent to the debug adapter.
  --- - `remove`: Remove the selected breakpoint
  --- - `expand`: Show/hide every property of the selected breakpoint
  --- - `collapse` (`<BS>`): Hide the properties again, from the breakpoint's
  ---   line or any of its property rows
  --- - `edit`: On a breakpoint, show its properties; on an expanded property,
  ---   change it (text is prompted for, true/false flips, custom properties
  ---   open their own editor)
  ---
  --- Other plugins can add properties; see |dapui.breakpoints|.
  dapui.elements.breakpoints = {
    allow_without_session = true,
  }

  local send_ready = util.create_render_loop(function()
    dapui.elements.breakpoints.render()
  end)

  local breakpoints = require("dapui.components.breakpoints")(client, send_ready)

  ---@nodoc
  function dapui.elements.breakpoints.render()
    local canvas = Canvas.new()
    breakpoints.render(canvas)
    canvas:render_buffer(dapui.elements.breakpoints.buffer(), config.element_mapping("breakpoints"))
  end

  ---@nodoc
  dapui.elements.breakpoints.buffer = util.create_buffer("DAP Breakpoints", {
    filetype = "dapui_breakpoints",
  })

  return dapui.elements.breakpoints
end
