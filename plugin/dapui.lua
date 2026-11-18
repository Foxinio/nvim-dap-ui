vim.api.nvim_create_user_command("DapRestoreLayout", function()
  require("dapui").restore_layout()
end, {
  desc = "Restore dap-ui panes to their configured positions and sizes",
  force = true,
})

vim.api.nvim_create_user_command("DapClean", function()
  require("dapui").debug_tab.clean()
end, {
  desc = "Terminate debugging, clear annotations and close the debugger panes and REPL",
  force = true,
})
