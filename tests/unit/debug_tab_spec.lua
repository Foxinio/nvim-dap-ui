local api = vim.api
local dap = require("dap")
local dapui = require("dapui")
local debug_tab = require("dapui.debug_tab")

describe("debug tab", function()
  local layouts = {
    { elements = { "scopes", "stacks" }, position = "left", size = 30 },
    { elements = { "repl" }, position = "bottom", size = 8 },
  }
  local original_tab, original_layout, session

  local function pane(name)
    local buffer = dapui.elements[name].buffer()
    for _, win in ipairs(api.nvim_tabpage_list_wins(debug_tab.tabpage())) do
      if api.nvim_win_get_buf(win) == buffer then
        return win
      end
    end
  end

  before_each(function()
    -- A fresh tab each time, so the previous test's debug tab is gone.
    vim.cmd("tabnew | silent! tabonly")
    vim.cmd("runtime plugin/dapui.lua")
    session = dap.session
    dapui.setup({ layouts = layouts, controls = { enabled = false } })
    vim.cmd("vsplit")
    original_tab = api.nvim_get_current_tabpage()
    original_layout = vim.fn.winlayout()
  end)

  after_each(function()
    dap.session = session
    package.loaded["tabby.feature.tab_name"] = nil
    pcall(dapui.close)
  end)

  it("opens the panes in a dedicated tab and leaves the editing tab alone", function()
    local tabs = #api.nvim_list_tabpages()
    dapui.open()
    local tab = api.nvim_get_current_tabpage()
    assert.Not.equal(original_tab, tab)
    assert.equal(tabs + 1, #api.nvim_list_tabpages())
    assert.is_truthy(pane("scopes") and pane("repl"))
    assert.same(original_layout, vim.fn.winlayout(api.nvim_tabpage_get_number(original_tab)))
    api.nvim_set_current_tabpage(original_tab)
    dapui.open()
    assert.equal(tab, api.nvim_get_current_tabpage())
    assert.equal(tabs + 1, #api.nvim_list_tabpages(), "the debug tab is reused")
  end)

  it("closes the panes in the debug tab and returns to the current tab", function()
    dapui.open()
    api.nvim_set_current_tabpage(original_tab)
    dapui.close()
    assert.equal(original_tab, api.nvim_get_current_tabpage())
    assert.is_nil(pane("scopes"))
  end)

  it("keeps the cursor in the REPL when opening and restoring from it", function()
    dapui.open()
    api.nvim_set_current_win(pane("repl"))
    api.nvim_win_set_width(pane("scopes"), 50)
    dapui.restore_layout()
    assert.equal(pane("repl"), api.nvim_get_current_win())
    assert.equal(30, api.nvim_win_get_width(pane("scopes")))
  end)

  it("restores the layout in the debug tab when called from another tab", function()
    dapui.open()
    api.nvim_win_close(pane("stacks"), true)
    api.nvim_set_current_tabpage(original_tab)
    vim.cmd("DapRestoreLayout")
    assert.equal(debug_tab.tabpage(), api.nvim_get_current_tabpage())
    assert.is_truthy(pane("stacks"))
    assert.same(original_layout, vim.fn.winlayout(api.nvim_tabpage_get_number(original_tab)))
  end)

  it("names the tab after the program when Tabby is installed", function()
    local names = {}
    package.loaded["tabby.feature.tab_name"] = {
      set = function(tab, name)
        names[tab] = name
      end,
      get_raw = function(tab)
        return names[tab] or ""
      end,
    }
    debug_tab.focus()
    local tab = api.nvim_get_current_tabpage()
    assert.equal("DEBUGGER", names[tab])
    dap.session = function()
      return { config = { program = "/work/build/my_app", name = "Launch" } }
    end
    debug_tab.focus()
    assert.equal("DEBUGGER (my_app)", names[tab])
    dap.session = function()
      return { config = { program = "", name = "Attach to application" } }
    end
    debug_tab.focus()
    assert.equal("DEBUGGER (Attach to application)", names[tab])
    dap.session = session
    debug_tab.focus()
    assert.equal("DEBUGGER (Attach to application)", names[tab], "keeps the target after exit")
    assert.is_nil(names[original_tab])
  end)

  it("reuses a surviving window when the source window was closed", function()
    dapui.open()
    local source = debug_tab.source_window()
    api.nvim_set_current_win(source)
    vim.cmd("vsplit")
    local survivor = api.nvim_get_current_win()
    api.nvim_win_close(source, true)
    local count = #api.nvim_tabpage_list_wins(debug_tab.tabpage())
    assert.equal(survivor, debug_tab.source_window())
    assert.equal(count, #api.nvim_tabpage_list_wins(debug_tab.tabpage()))
  end)

  it("behaves like upstream when disabled", function()
    dapui.setup({
      layouts = layouts,
      controls = { enabled = false },
      debug_tab = { enabled = false },
    })
    local tabs = #api.nvim_list_tabpages()
    dapui.open()
    assert.equal(tabs, #api.nvim_list_tabpages())
    assert.equal(original_tab, api.nvim_get_current_tabpage())
    dapui.close()
  end)
end)
