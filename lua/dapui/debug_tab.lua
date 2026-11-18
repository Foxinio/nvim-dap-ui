local api = vim.api

---@tag dapui.debug_tab
---@toc_entry Debug tab

---@text
--- With `debug_tab.enabled` (the default), debugging happens in one dedicated
--- tab page: the panes live there, and stack frames and breakpoints are
--- shown in its source window. Your editing
--- tabs and their splits are left alone. The tab is created on first use,
--- reused afterwards and recreated if it was closed.
---
--- `open()`, `toggle()` and `restore_layout()` switch to the debug tab before
--- changing anything (if you are already in it, the cursor stays where it is);
--- `close()` closes the panes there and returns to the tab you were in.
---
--- See |dapui.Config.debug_tab| for the options.

local dapui = {}

dapui.debug_tab = {}

local tab = nil --[[@as integer|nil]]
local source = nil --[[@as integer|nil]]

--- The `debug_tab` section of the config.
---@return dapui.Config.debug_tab
---@nodoc
local function config()
  return require("dapui.config").debug_tab or {}
end

--- Whether the debug tab is enabled in the config.
---@return boolean
function dapui.debug_tab.enabled()
  return config().enabled ~= false
end

--- Keep dap-ui's tracked source window in sync with the debug tab's.
---@param win integer
---@nodoc
local function track(win)
  require("dapui.source").set(win)
end

--- Whether `win` can serve as the source window (not a pane, REPL, terminal or float).
---@param win integer
---@return boolean
---@nodoc
local function is_source_candidate(win)
  local buffer = api.nvim_win_get_buf(win)
  local filetype = vim.bo[buffer].filetype
  return filetype ~= "dap-repl"
    and not filetype:match("^dapui_")
    and vim.bo[buffer].buftype ~= "terminal"
    and api.nvim_win_get_config(win).relative == ""
end

--- Make sure the debug tab and its source window exist (without focusing them).
---@nodoc
local function ensure_source()
  if not tab or not api.nvim_tabpage_is_valid(tab) then
    vim.cmd("tab split")
    tab = api.nvim_get_current_tabpage()
    source = api.nvim_get_current_win()
  elseif
    not source
    or not api.nvim_win_is_valid(source)
    or api.nvim_win_get_tabpage(source) ~= tab
  then
    source = nil
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if is_source_candidate(win) then
        source = win
        break
      end
    end
    if not source then
      api.nvim_win_call(api.nvim_tabpage_list_wins(tab)[1], function()
        vim.cmd("topleft new")
        source = api.nvim_get_current_win()
      end)
    end
  end
  track(source)
end

--- Name the debug tab after the debugged program when Tabby is installed.
---@nodoc
local function name_tab()
  if config().tabby == false then
    return
  end
  local ok, tab_name = pcall(require, "tabby.feature.tab_name")
  if not ok then
    return
  end
  local session = require("dap").session()
  local session_config = session and session.config
  if not session_config and tab_name.get_raw(tab) ~= "" then
    return
  end
  local target = session_config and session_config.name
  if
    session_config
    and type(session_config.program) == "string"
    and session_config.program ~= ""
  then
    target = vim.fn.fnamemodify(session_config.program, ":t")
  end
  tab_name.set(
    tab,
    type(target) == "string" and target ~= "" and ("DEBUGGER (" .. target .. ")") or "DEBUGGER"
  )
end

--- Make sure the debug tab exists and is named, without moving the cursor.
---@nodoc
local function ensure()
  ensure_source()
  name_tab()
end

--- The debug tab page, created if needed.
---@return integer tabpage
function dapui.debug_tab.tabpage()
  ensure()
  return tab --[[@as integer]]
end

--- The debug tab's source window, created if needed. dap-ui shows stack frame
--- and breakpoint locations here (it is the default `select_window`).
---@return integer win
function dapui.debug_tab.source_window()
  ensure_source()
  return source --[[@as integer]]
end

--- Switch to the debug tab and its source window.
function dapui.debug_tab.focus()
  ensure()
  api.nvim_set_current_win(source --[[@as integer]])
end

--- Run `fn` in the debug tab: switch to it first unless already there (then
--- the cursor stays where it is).
---@param fn fun(...): any
---@return any
function dapui.debug_tab.run(fn, ...)
  ensure()
  if api.nvim_get_current_tabpage() ~= tab then
    api.nvim_set_current_win(source --[[@as integer]])
  end
  return fn(...)
end

--- Run `fn` in the debug tab, then return to the tab you were in.
---@param fn fun(...): any
---@return any
function dapui.debug_tab.run_and_return(fn, ...)
  if not tab or not api.nvim_tabpage_is_valid(tab) then
    return
  end
  local previous = api.nvim_get_current_tabpage()
  api.nvim_set_current_tabpage(tab)
  local result = fn(...)
  if api.nvim_tabpage_is_valid(previous) then
    api.nvim_set_current_tabpage(previous)
  end
  return result
end

return dapui.debug_tab
