vim.api.nvim_create_user_command("DapRestoreLayout", function()
  require("dapui").restore_layout()
end, {
  desc = "Restore dap-ui panes to their configured positions and sizes",
  force = true,
})
