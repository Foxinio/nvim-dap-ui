local api = vim.api
local config = require("dapui.config")
local source_window = require("dapui.source")

describe("source window", function()
  local file_a, file_b, buf_a, buf_b

  local function new_file(lines)
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile(lines, path)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    return path, buf
  end

  before_each(function()
    vim.cmd("silent! only")
    vim.o.hidden = true
    config.setup({})
    source_window.set(nil)
    file_a, buf_a = new_file({ "a1", "a2", "a3" })
    file_b, buf_b = new_file({ "b1", "b2" })
  end)

  after_each(function()
    source_window.set(nil)
    vim.cmd("silent! only")
    for _, buf in ipairs({ buf_a, buf_b }) do
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
    vim.fn.delete(file_a)
    vim.fn.delete(file_b)
  end)

  it("tracks the window and keeps routing to it", function()
    local main = api.nvim_get_current_win()
    assert.is_true(source_window.open(buf_a, 2, 1))
    assert.equal(main, source_window.get())
    vim.cmd("vsplit")
    api.nvim_win_set_buf(0, buf_b)
    -- buf_b is visible elsewhere, but the tracked window wins.
    assert.is_true(source_window.open(buf_b, 1, 1))
    assert.equal(main, api.nvim_get_current_win())
    assert.equal(buf_b, api.nvim_win_get_buf(main))
  end)

  it("clamps lines and converts DAP columns", function()
    assert.is_true(source_window.open(buf_a, 99, 2))
    assert.same({ 3, 1 }, api.nvim_win_get_cursor(source_window.get()))
  end)

  it("can route without moving focus", function()
    local main = api.nvim_get_current_win()
    source_window.set(main)
    vim.cmd("vsplit")
    local other = api.nvim_get_current_win()
    assert.is_true(source_window.open(buf_b, 2, 1, { focus = false }))
    assert.equal(other, api.nvim_get_current_win())
    assert.equal(buf_b, api.nvim_win_get_buf(main))
  end)

  it("respects focus = false in the config", function()
    config.setup({ source_window = { focus = false } })
    local main = api.nvim_get_current_win()
    source_window.set(main)
    vim.cmd("vsplit")
    local other = api.nvim_get_current_win()
    source_window.open(buf_a, 1, 1)
    assert.equal(other, api.nvim_get_current_win())
  end)

  it("uses select_window once the tracked window is closed", function()
    vim.cmd("vsplit")
    local tracked = api.nvim_get_current_win()
    source_window.set(tracked)
    api.nvim_win_close(tracked, true)
    local chosen = api.nvim_get_current_win()
    config.setup({
      select_window = function()
        return chosen
      end,
    })
    assert.is_true(source_window.open(buf_a, 1, 1))
    assert.equal(chosen, source_window.get())
  end)

  it("labels only the tracked window", function()
    config.setup({ source_window = { winbar = "DAP Source" } })
    local main = api.nvim_get_current_win()
    source_window.open(buf_a, 1, 1)
    assert.equal("DAP Source", vim.wo[main].winbar)
    -- A buffer shown for the first time resets window-local options.
    source_window.open(buf_b, 1, 1)
    assert.equal("DAP Source", vim.wo[main].winbar)
    vim.cmd("split")
    assert.equal("", vim.wo[api.nvim_get_current_win()].winbar)
    source_window.set(api.nvim_get_current_win())
    assert.equal("", vim.wo[main].winbar)
  end)

  it("reports instead of discarding unsaved changes with nohidden", function()
    vim.o.hidden = false
    local main = api.nvim_get_current_win()
    source_window.open(buf_a, 1, 1)
    api.nvim_buf_set_lines(buf_a, 0, 1, false, { "edited" })
    local notify = vim.notify
    local messages = {}
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    local opened = source_window.open(buf_b, 1, 1)
    vim.wait(200, function()
      return #messages > 0
    end)
    vim.notify = notify
    assert.is_false(opened)
    assert.equal(buf_a, api.nvim_win_get_buf(main))
    assert.equal("edited", api.nvim_buf_get_lines(buf_a, 0, 1, false)[1])
    assert.is_true(#messages > 0)
    vim.bo[buf_a].modified = false
  end)
end)
