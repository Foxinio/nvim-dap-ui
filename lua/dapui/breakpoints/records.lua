--- Records of stored properties, anchored to breakpoints with extmarks, and
--- stable handles to breakpoints. Nothing nvim-dap stores is kept here.
local M = {}

local api = vim.api
M.ns = api.nvim_create_namespace("dapui_breakpoint_properties")
local ns = M.ns

--- Backend holding nvim-dap's breakpoints. Replaceable for tests.
M.backend = require("dap.breakpoints")

--- buffer → extmark id → record
---@type table<integer, table<integer, { props: table<string, any>, anchors: integer }>>
local records = {}
--- handle → { buf, mark }
local handles = {}
local next_handle = 0

--- nvim-dap's breakpoints of a buffer, by line.
---@param bufnr integer
---@return table<integer, dapui.breakpoints.Breakpoint>
function M.breakpoints(bufnr)
  local result = {}
  if not api.nvim_buf_is_valid(bufnr) then
    return result
  end
  for _, bp in ipairs(M.backend.get(bufnr)[bufnr] or {}) do
    bp.buf = bp.buf or bufnr
    result[bp.line] = bp
  end
  return result
end

--- Drop records whose breakpoint is gone, and duplicates left on one line.
function M.prune(bufnr)
  local buf_records = records[bufnr]
  if not buf_records then
    return
  end
  if not api.nvim_buf_is_valid(bufnr) then
    records[bufnr] = nil
    return
  end
  local bps = M.breakpoints(bufnr)
  local seen = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    local id, line = mark[1], mark[2] + 1
    local record = buf_records[id]
    if record and (not bps[line] or seen[line]) then
      api.nvim_buf_del_extmark(bufnr, ns, id)
      buf_records[id] = nil
    elseif record then
      seen[line] = true
    end
  end
  -- Records whose extmark was removed with its text.
  for id in pairs(buf_records) do
    if not api.nvim_buf_get_extmark_by_id(bufnr, ns, id, {})[1] then
      buf_records[id] = nil
    end
  end
end

---@return integer? mark, table? record
function M.find(bufnr, line)
  local buf_records = records[bufnr]
  if not buf_records then
    return
  end
  local marks = api.nvim_buf_get_extmarks(bufnr, ns, { line - 1, 0 }, { line - 1, -1 }, {})
  for _, mark in ipairs(marks) do
    if buf_records[mark[1]] then
      return mark[1], buf_records[mark[1]]
    end
  end
end

function M.ensure(bufnr, line)
  local mark, record = M.find(bufnr, line)
  if record then
    return mark, record
  end
  mark = api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {})
  record = { props = {}, anchors = 0 }
  records[bufnr] = records[bufnr] or {}
  records[bufnr][mark] = record
  return mark, record
end

--- Delete a record that holds nothing and is not anchored by a handle.
function M.drop_if_default(bufnr, mark, record)
  if record.anchors > 0 or next(record.props) ~= nil then
    return
  end
  M.delete(bufnr, mark)
end

function M.delete(bufnr, mark)
  api.nvim_buf_del_extmark(bufnr, ns, mark)
  records[bufnr][mark] = nil
end

--- Records of a buffer with their extmark position, in buffer order.
---@return { mark: integer, line: integer, record: table }[]
function M.placed(bufnr)
  local result = {}
  if not records[bufnr] or not api.nvim_buf_is_valid(bufnr) then
    return result
  end
  for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
    local record = records[bufnr][mark[1]]
    if record then
      result[#result + 1] = { mark = mark[1], line = mark[2] + 1, record = record }
    end
  end
  return result
end

function M.handle(bufnr, line)
  M.prune(bufnr)
  if not M.breakpoints(bufnr)[line] then
    return nil
  end
  local mark, record = M.ensure(bufnr, line)
  for handle, target in pairs(handles) do
    if target.buf == bufnr and target.mark == mark then
      return handle
    end
  end
  next_handle = next_handle + 1
  handles[next_handle] = { buf = bufnr, mark = mark }
  record.anchors = record.anchors + 1
  return next_handle
end

function M.locate(handle)
  local target = handles[handle]
  if not target then
    return
  end
  M.prune(target.buf)
  local record = records[target.buf] and records[target.buf][target.mark]
  if not record then
    handles[handle] = nil
    return
  end
  local position = api.nvim_buf_get_extmark_by_id(target.buf, ns, target.mark, {})
  return target.buf, position[1] + 1
end

function M.release(handle)
  local target = handles[handle]
  handles[handle] = nil
  if not target then
    return
  end
  local record = records[target.buf] and records[target.buf][target.mark]
  if record then
    record.anchors = record.anchors - 1
    M.drop_if_default(target.buf, target.mark, record)
  end
end

api.nvim_create_autocmd("BufWipeout", {
  group = api.nvim_create_augroup("dapui.breakpoints", { clear = true }),
  callback = function(args)
    records[args.buf] = nil
  end,
})

return M
