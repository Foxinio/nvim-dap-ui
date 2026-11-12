-- Test init: dependencies from DEPS_DIR or lazy.nvim's plugin directory.
local deps = vim.env.DEPS_DIR
if not deps or deps == "" then
  deps = vim.fn.stdpath("data") .. "/lazy"
end
deps = vim.fn.fnamemodify(deps, ":p"):gsub("/$", "")
vim.opt.rtp:append(".")
for _, name in ipairs({ "plenary.nvim", "nvim-dap", "nvim-nio" }) do
  vim.opt.rtp:append(deps .. "/" .. name)
end
vim.opt.swapfile = false
vim.cmd("runtime! plugin/plenary.vim")
