# dotfiles

Personal Neovim ([LazyVim](https://www.lazyvim.org/)), tmux, and [Starship](https://starship.rs/) config.

## Prerequisites

- Neovim ≥ 0.9 (LazyVim requirement)
- tmux
- [Starship](https://starship.rs/)
- git, curl, a C compiler (for Treesitter), and [ripgrep](https://github.com/BurntSushi/ripgrep) + [fd](https://github.com/sharkdp/fd) (LazyVim defaults expect them)
- A [Nerd Font](https://www.nerdfonts.com/) set as your terminal font (LazyVim *and* Starship use font icons)
- Optional: [`himalaya`](https://github.com/pimalaya/himalaya) CLI — needed for the email plugin to actually do anything

On macOS:

```sh
brew install neovim tmux starship ripgrep fd
```

## Install

1. Clone this repo (path doesn't matter, examples assume `~/writing/dotfiles`):

   ```sh
   git clone <this-repo> ~/writing/dotfiles
   ```

2. Run the setup script:

   ```sh
   cd ~/writing/dotfiles
   ./setup.sh
   ```

   It symlinks `nvim/` → `~/.config/nvim`, `tmux/.tmux.conf` → `~/.tmux.conf`, and `starship/starship.toml` → `~/.config/starship.toml`, then checks the required tools above and prints the `brew install` line for anything missing. It's idempotent (safe to re-run) and refuses to clobber a pre-existing non-empty `init.lua`, `init.vim`, `.tmux.conf`, or `starship.toml` — back the file up and re-run if it warns.

3. Hook Starship into your shell. The setup script tells you exactly what to paste; for reference:

   ```sh
   # zsh — append to ~/.zshrc
   eval "$(starship init zsh)"

   # bash — append to ~/.bashrc (or ~/.bash_profile on macOS login shells)
   eval "$(starship init bash)"
   ```

   Open a new shell to pick it up.

4. Launch `nvim`. On first run, `nvim/lua/config/lazy.lua` bootstraps `lazy.nvim` itself (clones it into Neovim's data dir), then installs every plugin under `nvim/lua/plugins/`. The `fzf` plugin's `build` step compiles the fzf binary automatically.

5. Start tmux with `tmux`. Reload after editing `.tmux.conf` with `prefix r` (`C-b r` by default — the prefix is not remapped).

## What's inside

- `nvim/` — Neovim config layered on LazyVim. Custom plugins live in `nvim/lua/plugins/`:
  - `tmux.lua` — `vim-tmux-navigator` for Ctrl-h/j/k/l pane navigation (paired with `tmux/.tmux.conf`).
  - `himalaya.lua` — `himalaya-vim` email client.
  - `fzf.lua` — `junegunn/fzf` + `fzf.vim`.
- `tmux/.tmux.conf` — terminal defaults, mouse on, and the tmux side of seamless Vim/tmux Ctrl-h/j/k/l navigation.
- `starship/starship.toml` — Starship prompt config. Reloads automatically on the next prompt render — no command needed.

## Updating plugins

Inside Neovim: `:Lazy sync` (LazyVim also has `checker.enabled = true`, which notifies of updates automatically).

## Notes

There is no vim-plug in this setup — `lazy.nvim` is the only plugin manager. If you see references to `Plug` anywhere, it's stale.

See `CLAUDE.md` for architecture notes when editing.
