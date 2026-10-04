-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://www.lazyvim.org/configuration/general#auto-commands

-- Write Session.vim on exit (only inside tmux) so tmux-resurrect's
-- nvim 'session' strategy can restore the editor after a reboot.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("tmux_resurrect_session", { clear = true }),
  callback = function()
    if vim.env.TMUX then
      pcall(vim.cmd, "mksession! Session.vim")
    end
  end,
})
