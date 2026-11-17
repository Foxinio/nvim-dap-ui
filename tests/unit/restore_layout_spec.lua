local api = vim.api
local dapui = require("dapui")

describe("restore_layout", function()
  local layouts = {
    {
      elements = { { id = "scopes", size = 0.6 }, { id = "stacks", size = 0.4 } },
      position = "left",
      size = 30,
    },
    { elements = { "repl" }, position = "bottom", size = 8 },
  }

  -- Window tree with each window named by its dap-ui element (or "editor").
  local function shape()
    local names = {}
    for name, elem in pairs(dapui.elements) do
      names[elem.buffer()] = name
    end
    local function walk(node)
      if node[1] == "leaf" then
        return names[api.nvim_win_get_buf(node[2])] or "editor"
      end
      local children = {}
      for _, child in ipairs(node[2]) do
        children[#children + 1] = walk(child)
      end
      return { node[1], children }
    end
    return walk(vim.fn.winlayout())
  end

  local function win_of(name)
    return vim.fn.bufwinid(dapui.elements[name].buffer())
  end

  local function sizes()
    return {
      scopes = api.nvim_win_get_width(win_of("scopes")),
      repl = api.nvim_win_get_height(win_of("repl")),
    }
  end

  local fresh_shape, fresh_sizes, editor
  before_each(function()
    vim.cmd("silent! tabonly | silent! only")
    dapui.setup({ layouts = layouts, controls = { enabled = false } })
    editor = api.nvim_get_current_win()
    dapui.open()
    fresh_shape, fresh_sizes = shape(), sizes()
  end)

  after_each(function()
    dapui.close()
  end)

  it("restores resized, closed and moved panes", function()
    api.nvim_win_set_width(win_of("scopes"), 50)
    api.nvim_win_set_height(win_of("repl"), 3)
    api.nvim_win_close(win_of("stacks"), true)
    api.nvim_set_current_win(win_of("repl"))
    vim.cmd("wincmd L")
    api.nvim_set_current_win(editor)
    assert.Not.same(fresh_shape, shape())

    dapui.restore_layout()

    assert.same(fresh_shape, shape())
    assert.same(fresh_sizes, sizes())
    assert.equal(editor, api.nvim_get_current_win())
  end)

  it("puts element buffers back into panes that show another buffer", function()
    local other = api.nvim_create_buf(true, true)
    api.nvim_win_set_buf(win_of("scopes"), other)
    dapui.restore_layout()
    assert.same(fresh_shape, shape())
    api.nvim_buf_delete(other, { force = true })
  end)

  it("keeps the user's own splits", function()
    api.nvim_set_current_win(editor)
    vim.cmd("vsplit")
    local split = api.nvim_get_current_win()
    api.nvim_win_set_width(win_of("scopes"), 50)

    dapui.restore_layout()

    assert.is_true(api.nvim_win_is_valid(split))
    assert.is_true(api.nvim_win_is_valid(editor))
    assert.equal(split, api.nvim_get_current_win())
    assert.same(fresh_sizes, sizes())
  end)

  it("keeps the cursor in its pane", function()
    api.nvim_set_current_win(win_of("stacks"))
    api.nvim_win_set_width(win_of("scopes"), 50)
    dapui.restore_layout()
    assert.equal(dapui.elements.stacks.buffer(), api.nvim_get_current_buf())
  end)

  it("focuses the debugger tab first and restores there", function()
    local debug_tab = api.nvim_get_current_tabpage()
    api.nvim_win_set_width(win_of("scopes"), 50)
    vim.cmd("tabnew")
    local other_tab = api.nvim_get_current_tabpage()
    local other_wins = api.nvim_tabpage_list_wins(other_tab)

    dapui.restore_layout()

    assert.equal(debug_tab, api.nvim_get_current_tabpage())
    assert.same(fresh_shape, shape())
    assert.same(fresh_sizes, sizes())
    assert.same(other_wins, api.nvim_tabpage_list_wins(other_tab))
    vim.cmd("tabclose " .. api.nvim_tabpage_get_number(other_tab))
  end)

  it("restores in one quick synchronous call", function()
    api.nvim_win_close(win_of("stacks"), true)
    api.nvim_win_set_height(win_of("repl"), 3)
    local start = vim.uv.hrtime()
    dapui.restore_layout()
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
    assert.same(fresh_shape, shape())
    assert.is_true(elapsed_ms < 50, ("restore took %.1f ms"):format(elapsed_ms))
  end)

  it("is available as :DapRestoreLayout", function()
    vim.cmd("runtime plugin/dapui.lua")
    api.nvim_win_close(win_of("stacks"), true)
    vim.cmd("DapRestoreLayout")
    assert.same(fresh_shape, shape())
  end)
end)
