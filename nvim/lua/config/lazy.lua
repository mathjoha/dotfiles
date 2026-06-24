local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- Import LazyVim specifications
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- Import pre-configured languages (Python)
    { import = "lazyvim.plugins.extras.lang.python" },
    -- Import user custom plugins
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  checker = { enabled = true },
})
