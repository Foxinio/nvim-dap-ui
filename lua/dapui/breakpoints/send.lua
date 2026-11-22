--- Sending breakpoints to debug sessions, holding back inactive ones.
local M = {}

local records = require("dapui.breakpoints.records")
local rules = require("dapui.breakpoints.rules")
local signs = require("dapui.breakpoints.signs")

function M.changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "DapUIBreakpointsChanged", modeline = false })
end

local function broadcast(sessions, fn)
  for _, session in pairs(sessions or {}) do
    fn(session)
    broadcast(session.children, fn)
  end
end

--- Make a session leave out inactive breakpoints whenever it sends them.
function M.wrap(session)
  if rawget(session, "set_breakpoints") then
    return
  end
  local original = session.set_breakpoints
  session.set_breakpoints = function(self, bps, on_done)
    local filtered = {}
    for bufnr, buf_bps in pairs(bps) do
      records.prune(bufnr)
      filtered[bufnr] = vim.tbl_filter(function(bp)
        bp.buf = bp.buf or bufnr
        local _, record = records.find(bufnr, bp.line)
        return rules.active(bp, record)
      end, buf_bps)
      signs.update(bufnr)
    end
    return original(self, filtered, on_done)
  end
end

--- Send breakpoints (one buffer's or all) to every session again.
function M.refresh(bufnr)
  local bps = bufnr and records.backend.get(bufnr) or records.backend.get()
  if bufnr then
    bps[bufnr] = bps[bufnr] or {}
  end
  for buf in pairs(bps) do
    signs.update(buf)
  end
  local ok, dap = pcall(require, "dap")
  if ok and next(bps) then
    broadcast(dap.sessions(), function(session)
      session:set_breakpoints(bps)
    end)
  end
  M.changed()
end

--- Wrap existing sessions and every new one before it sends breakpoints.
function M.install()
  local dap = require("dap")
  dap.listeners.before.event_initialized["dapui.breakpoints"] = function(session)
    M.wrap(session)
  end
  broadcast(dap.sessions(), M.wrap)
end

return M
