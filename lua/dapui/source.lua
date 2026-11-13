local api = vim.api

---@tag dapui.source_window
---@toc_entry Source window

---@text
--- Debugger source navigation (stack frames, breakpoints) is routed to one
--- tracked "source window" per session. The window displays the real file
--- buffers, so editing, saving, undo, LSP and Tree-sitter behave as in any
--- other window. Routing and focusing are separate: `open` can update the
--- window without moving the cursor into it.
---
--- Resolution order for the destination window:
--- 1. The tracked window, while it is valid and in the current tab page.
--- 2. `select_window()` from the config, when provided.
--- 3. A window in the current tab page already showing the buffer.
--- 4. The interactive window picker.
---
--- See |dapui.Config.source_window| for the related options.

local dapui = {}

dapui.source_window = {}

local tracked
local group = api.nvim_create_augroup("DapUISourceWindow", { clear = true })

---@nodoc
local function config()
  return require("dapui.config").source_window or {}
end

local function in_current_tab(win)
  return win
    and api.nvim_win_is_valid(win)
    and api.nvim_win_get_tabpage(win) == api.nvim_get_current_tabpage()
end

local function set_label(win)
  local label = config().winbar
  if label and label ~= "" and api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = label
  end
end

local function clear_label(win)
  local label = config().winbar
  if label and win and api.nvim_win_is_valid(win) and vim.wo[win].winbar == label then
    vim.wo[win].winbar = ""
  end
end

-- Window-local options are reset when a buffer is first shown in a window,
-- and copied into splits. Keep the label on the tracked window only.
api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function()
    if tracked and api.nvim_get_current_win() == tracked then
      set_label(tracked)
    end
  end,
})
api.nvim_create_autocmd("WinNew", {
  group = group,
  callback = function()
    local win = api.nvim_get_current_win()
    if win ~= tracked then
      clear_label(win)
    end
  end,
})

--- Get the tracked source window.
---@return integer|nil
function dapui.source_window.get()
  if tracked and api.nvim_win_is_valid(tracked) then
    return tracked
  end
  tracked = nil
end

--- Track `win` as the source window (nil stops tracking).
---@param win integer|nil
function dapui.source_window.set(win)
  if win == tracked then
    if win then
      set_label(win)
    end
    return
  end
  clear_label(tracked)
  tracked = win
  if win then
    set_label(win)
  end
end

---@return integer|nil
---@nodoc
local function resolve(bufnr)
  if config().track ~= false and in_current_tab(tracked) then
    return tracked
  end
  local cfg = require("dapui.config")
  if cfg.select_window then
    local ok, win = pcall(cfg.select_window)
    if ok and win and api.nvim_win_is_valid(win) then
      return win
    end
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  local ok, win = pcall(require("dapui.util").select_win)
  if ok and win and api.nvim_win_is_valid(win) then
    return win
  end
end

---@class dapui.source_window.OpenArgs
---@field focus? boolean Move the cursor into the source window. Defaults to
--- `source_window.focus` from the config.

--- Show `bufnr` in the source window and place the cursor.
---@param bufnr integer
---@param line? integer 1-based line, clamped to the buffer length
---@param column? integer 1-based column
---@param args? dapui.source_window.OpenArgs
---@return boolean opened
function dapui.source_window.open(bufnr, line, column, args)
  args = args or {}
  local win = resolve(bufnr)
  if not win then
    return false
  end
  if api.nvim_win_get_buf(win) ~= bufnr then
    local ok, err = pcall(api.nvim_win_set_buf, win, bufnr)
    if not ok then
      -- e.g. E37 with 'nohidden' while the window shows a modified buffer.
      require("dapui.util").notify(err, vim.log.levels.WARN)
      return false
    end
  end
  if line then
    line = math.max(1, math.min(line, api.nvim_buf_line_count(bufnr)))
    pcall(api.nvim_win_set_cursor, win, { line, math.max(0, (column or 1) - 1) })
  end
  if config().track ~= false then
    dapui.source_window.set(win)
  end
  local focus = args.focus
  if focus == nil then
    focus = config().focus ~= false
  end
  if focus then
    pcall(api.nvim_set_current_win, win)
  end
  return true
end

return dapui.source_window
