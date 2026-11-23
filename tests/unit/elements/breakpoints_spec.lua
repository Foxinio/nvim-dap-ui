local nio = require("nio")
local Breakpoints = require("dapui.elements.breakpoints")
local a = nio.tests
local tests = require("dapui.tests")
tests.bootstrap()
local mocks = tests.mocks

describe("breakpoints element", function()
  local client, breakpoints, buf
  local init_bps = {
    test_a = {
      lines = {
        "line_a_1",
        "line_a_2",
        "line_a_3",
      },
      bps = {
        [1] = {},
        [3] = { condition = "a + 3 == 3" },
      },
    },
    test_b = {
      lines = {
        "line_b_1",
        "line_b_2",
        "line_b_3",
      },
      bps = {
        [2] = { log_message = "here" },
      },
    },
  }
  a.before_each(function()
    client = mocks.client({
      current_frame = {
        id = 1,
        line = 1,
        source = {
          path = "test_a",
        },
      },
    })
    for path, data in pairs(init_bps) do
      local path_buf = vim.api.nvim_create_buf(true, true)
      nio.api.nvim_buf_set_name(path_buf, path)
      nio.api.nvim_buf_set_lines(path_buf, 0, -1, false, data.lines)
      for line, bp in pairs(data.bps) do
        require("dap.breakpoints").toggle(vim.deepcopy(bp), path_buf, line)
      end
    end
    breakpoints = Breakpoints(client)
    breakpoints.render()
    buf = breakpoints.buffer()
  end)

  after_each(function()
    -- Stop this test's render loop so a late redraw can't recreate its buffer.
    require("dapui.util").stop_render_tasks()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    for path, _ in pairs(init_bps) do
      local path_buf = vim.fn.bufnr(path)
      pcall(vim.api.nvim_buf_delete, path_buf, { force = true })
    end
    breakpoints = nil
    require("dap.breakpoints").clear()
  end)

  a.it("renders lines", function()
    local lines = nio.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same({
      "test_a:",
      " 1 line_a_1",
      " 3 line_a_3",
      "   Condition: a + 3 == 3",
      "",
      "test_b:",
      " 2 line_b_2",
      "   Log Message: here",
    }, lines)
  end)

  a.it("renders highlights", function()
    local highlights = tests.util.get_highlights(buf)
    assert.same({
      { "DapUIBreakpointsPath", 0, 0, 0, 6 },
      { "DapUIBreakpointsCurrentLine", 1, 1, 1, 2 },
      { "DapUIBreakpointsLine", 2, 1, 2, 2 },
      { "DapUIBreakpointsInfo", 3, 3, 3, 13 },
      { "DapUIBreakpointsPath", 5, 0, 5, 6 },
      { "DapUIBreakpointsLine", 6, 1, 6, 2 },
      { "DapUIBreakpointsInfo", 7, 3, 7, 15 },
    }, highlights)
  end)

  a.it("renders highlights with toggled breakpoint", function()
    local keymaps = tests.util.get_mappings(buf)
    keymaps.t(3)
    nio.sleep(10)
    local highlights = tests.util.get_highlights(buf)
    assert.same({
      { "DapUIBreakpointsPath", 0, 0, 0, 6 },
      { "DapUIBreakpointsCurrentLine", 1, 1, 1, 2 },
      { "DapUIBreakpointsDisabledLine", 2, 1, 2, 2 },
      { "DapUIBreakpointsInfo", 3, 3, 3, 13 },
      { "DapUIBreakpointsPath", 5, 0, 5, 6 },
      { "DapUIBreakpointsLine", 6, 1, 6, 2 },
      { "DapUIBreakpointsInfo", 7, 3, 7, 15 },
    }, highlights)
  end)

  a.it("removes a disabled breakpoint", function()
    local keymaps = tests.util.get_mappings(buf)
    keymaps.t(3)
    keymaps = tests.util.get_mappings(buf)
    keymaps.d(3)
    nio.sleep(10)
    local lines = nio.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same(
      { "test_a:", " 1 line_a_1", "", "test_b:", " 2 line_b_2", "   Log Message: here" },
      lines
    )
  end)
  a.it("keeps a disabled breakpoint in nvim-dap but does not send it", function()
    local keymaps = tests.util.get_mappings(buf)
    keymaps.t(3)
    local path_buf = vim.fn.bufnr("test_a")
    local bps = require("dap.breakpoints").get(path_buf)[path_buf]
    assert.same(2, #bps)
    local sent
    local session = setmetatable({}, {
      __index = {
        set_breakpoints = function(_, payload)
          sent = payload
        end,
      },
    })
    require("dap").listeners.before.event_initialized["dapui.breakpoints"](session)
    session:set_breakpoints(require("dap.breakpoints").get(path_buf))
    assert.same(
      { 1 },
      vim.tbl_map(function(bp)
        return bp.line
      end, sent[path_buf])
    )
    assert.is_false(require("dapui.breakpoints").is_active(path_buf, 3))
    assert.same("a + 3 == 3", bps[2].condition or bps[1].condition)
  end)

  a.it("expands a breakpoint into its properties", function()
    local keymaps = tests.util.get_mappings(buf)
    keymaps["<CR>"](3)
    nio.sleep(10)
    local lines = nio.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same({
      "test_a:",
      " 1 line_a_1",
      " 3 line_a_3",
      "   Enabled: true",
      "   Condition: a + 3 == 3",
      "   Hit Condition: (none)",
      "   Log Message: (none)",
      "",
      "test_b:",
      " 2 line_b_2",
      "   Log Message: here",
    }, lines)
  end)

  a.it("edits a condition in nvim-dap", function()
    local keymaps = tests.util.get_mappings(buf)
    keymaps["<CR>"](3)
    nio.sleep(10)
    local input = vim.ui.input
    vim.ui.input = function(opts, cb)
      assert.same("a + 3 == 3", opts.default)
      cb("a > 1")
    end
    keymaps = tests.util.get_mappings(buf)
    keymaps.e(5)
    vim.ui.input = input
    local path_buf = vim.fn.bufnr("test_a")
    local bp = require("dapui.breakpoints").breakpoint(path_buf, 3)
    assert.same("a > 1", bp.condition)
  end)

  a.it("shows, edits and drops registered properties", function()
    local store = require("dapui.breakpoints")
    local path_buf = vim.fn.bufnr("test_a")
    store.register("note", {
      label = "Note",
      type = "string",
      default = nil,
    })
    nio.sleep(10)
    local keymaps = tests.util.get_mappings(buf)
    keymaps["<CR>"](2)
    nio.sleep(10)
    local lines = nio.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same("   Note: (none)", lines[7])
    local input = vim.ui.input
    vim.ui.input = function(_, cb)
      cb("look here")
    end
    keymaps = tests.util.get_mappings(buf)
    keymaps.e(7)
    vim.ui.input = input
    assert.same("look here", store.get(path_buf, 1, "note"))
    keymaps = tests.util.get_mappings(buf)
    keymaps["<CR>"](2)
    nio.sleep(10)
    lines = nio.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same("   Note: look here", lines[3])
    local marks = vim.api.nvim_buf_get_extmarks(
      path_buf,
      vim.api.nvim_get_namespaces()["dapui_breakpoint_properties"],
      0,
      -1,
      {}
    )
    assert.same(1, #marks)
    store.set(path_buf, 1, "note", nil)
    marks = vim.api.nvim_buf_get_extmarks(
      path_buf,
      vim.api.nvim_get_namespaces()["dapui_breakpoint_properties"],
      0,
      -1,
      {}
    )
    assert.same(0, #marks)
  end)

  a.it("holds back breakpoints a rule rejects", function()
    local store = require("dapui.breakpoints")
    local path_buf = vim.fn.bufnr("test_a")
    store.add_rule("test", function(bp)
      return bp.line ~= 1
    end)
    assert.is_false(store.is_active(path_buf, 1))
    assert.is_true(store.is_active(path_buf, 3))
    store.remove_rule("test")
    assert.is_true(store.is_active(path_buf, 1))
  end)

  a.it("follows a breakpoint through edits with a handle", function()
    local store = require("dapui.breakpoints")
    local path_buf = vim.fn.bufnr("test_a")
    local handle = store.handle(path_buf, 3)
    nio.api.nvim_buf_set_lines(path_buf, 0, 0, false, { "new line" })
    local located_buf, line = store.locate(handle)
    assert.same(path_buf, located_buf)
    assert.same(4, line)
    store.release(handle)
  end)

  a.it("redraws after a change made while text is locked", function()
    local notify, messages = vim.notify, {}
    vim.notify = function(message)
      messages[#messages + 1] = message
    end
    local path_buf = vim.fn.bufnr("test_a")
    -- An expression mapping runs with textlock, like completion or statusline code.
    vim.keymap.set("n", "<F13>", function()
      require("dapui.breakpoints").set(path_buf, 3, "enabled", false)
      return ""
    end, { expr = true })
    nio.api.nvim_feedkeys(vim.keycode("<F13>"), "xt", false)
    nio.sleep(50)
    vim.notify = notify
    vim.keymap.del("n", "<F13>")
    assert.same({}, messages)
    assert.same({ "DapUIBreakpointsDisabledLine", 2, 1, 2, 2 }, tests.util.get_highlights(buf)[3])
  end)
end)
