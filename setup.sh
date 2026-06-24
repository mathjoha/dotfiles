#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NVIM_SRC="$SCRIPT_DIR/nvim"
NVIM_DST="$HOME/.config/nvim"
TMUX_SRC="$SCRIPT_DIR/tmux/.tmux.conf"
TMUX_DST="$HOME/.tmux.conf"
STARSHIP_SRC="$SCRIPT_DIR/starship/starship.toml"
STARSHIP_DST="$HOME/.config/starship.toml"

if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_INFO=$'\033[1;34m'; C_RST=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_INFO=''; C_RST=''
fi

LINK_CONFLICTS=0
DEP_WARNINGS=0

log()      { printf '%s==>%s %s\n' "$C_INFO" "$C_RST" "$*"; }
ok()       { printf '%s ok%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn()     { printf '%s !!%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
conflict() { warn "$*"; LINK_CONFLICTS=$((LINK_CONFLICTS+1)); }
dep_warn() { warn "$*"; DEP_WARNINGS=$((DEP_WARNINGS+1)); }

# Print the path of the first non-empty init.lua / init.vim under $1, or return 1.
find_nonempty_init() {
  local dir="$1"
  for f in "$dir/init.lua" "$dir/init.vim"; do
    if [[ -f "$f" && -s "$f" ]]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

link_path() {
  local src="$1" dst="$2" label="$3"

  # Already pointing at our repo? Idempotent no-op.
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    ok "$label already linked: $dst -> $src"
    return
  fi

  # Symlink, but pointing elsewhere.
  if [[ -L "$dst" ]]; then
    conflict "$label: $dst is a symlink to $(readlink "$dst"). Move it aside and re-run."
    return
  fi

  # Existing directory at the destination.
  if [[ -d "$dst" ]]; then
    if conflict=$(find_nonempty_init "$dst"); then
      conflict "$label: $conflict exists and is non-empty. Back up $dst, then re-run."
    else
      conflict "$label: $dst already exists. Back up or remove it, then re-run."
    fi
    return
  fi

  # Existing non-empty file at the destination.
  if [[ -f "$dst" && -s "$dst" ]]; then
    conflict "$label: $dst exists and is non-empty. Back it up, then re-run."
    return
  fi

  # Empty file lingering — safe to clear.
  [[ -e "$dst" ]] && rm -f "$dst"

  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  ok "$label linked: $dst -> $src"
}

check_nerd_font() {
  # Try fontconfig first (Linux ships it; on macOS it requires `brew install fontconfig`).
  if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi 'nerd font'; then
    ok "Nerd Font detected (via fc-list)"
    return 0
  fi

  # Fall back to scanning the standard font directories (covers macOS without fontconfig
  # and Linux desktops where the font was dropped in by hand).
  local dirs=(
    "$HOME/Library/Fonts"
    /Library/Fonts
    /System/Library/Fonts
    "$HOME/.local/share/fonts"
    /usr/share/fonts
  )
  local dir hit
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    hit=$(find "$dir" -maxdepth 3 -iname '*nerd*font*' 2>/dev/null | head -n 1)
    if [[ -n "$hit" ]]; then
      ok "Nerd Font detected: $hit"
      return 0
    fi
  done

  dep_warn "No Nerd Font detected — LazyVim's icons will render as boxes/?"
  if command -v brew >/dev/null 2>&1; then
    printf '    Install with Homebrew (any one):\n'
    printf '      brew install --cask font-jetbrains-mono-nerd-font\n'
    printf '      brew install --cask font-hack-nerd-font\n'
    printf '      brew install --cask font-fira-code-nerd-font\n'
  else
    printf '    Pick one from https://www.nerdfonts.com/font-downloads\n'
    printf '    and drop the .ttf files into ~/.local/share/fonts (then: fc-cache -f).\n'
  fi
  printf '    After installing, set it as your terminal font.\n'
}

check_starship_shell_init() {
  local shell_name="${SHELL##*/}"
  local init_line
  local -a candidates=()

  case "$shell_name" in
    zsh)
      init_line='eval "$(starship init zsh)"'
      candidates=("$HOME/.zshrc")
      ;;
    bash)
      init_line='eval "$(starship init bash)"'
      # macOS login shells read .bash_profile; interactive non-login read .bashrc.
      candidates=("$HOME/.bashrc" "$HOME/.bash_profile")
      ;;
    fish)
      init_line='starship init fish | source'
      candidates=("$HOME/.config/fish/config.fish")
      ;;
    *)
      dep_warn "Unknown shell ($SHELL) — wire up starship init manually."
      printf '    https://starship.rs/#step-2-set-up-your-shell-to-use-starship\n'
      return 0
      ;;
  esac

  local rcfile
  for rcfile in "${candidates[@]}"; do
    if [[ -f "$rcfile" ]] && grep -q 'starship init' "$rcfile" 2>/dev/null; then
      ok "Starship shell init found in $rcfile"
      return 0
    fi
  done

  dep_warn "Starship shell init not found in your $shell_name rc."
  printf '    Add this line to %s (create the file if missing):\n' "${candidates[0]}"
  printf '      %s\n' "$init_line"
  printf '    Then open a new shell.\n'
}

macos_terminal_reminder() {
  [[ "$OSTYPE" == darwin* ]] || return 0
  printf '    macOS reminder: installing a Nerd Font does NOT change your terminal'\''s font.\n'
  printf '      Terminal.app: Settings → Profiles → Text → Font → Change…\n'
  printf '      Pick "JetBrainsMono Nerd Font" (avoid the variant with a "Mono" suffix).\n'
  printf '      Quick test in the terminal: printf '\''\\uf07c \\uf002 \\uf007\\n'\''\n'
}

check_deps() {
  log "Checking dependencies"
  local required=(nvim tmux git rg fd starship)
  local missing=()
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "All required tools present: ${required[*]}"
  else
    dep_warn "Missing tools: ${missing[*]}"
    if command -v brew >/dev/null 2>&1; then
      local formulas=()
      for m in "${missing[@]}"; do
        case "$m" in
          rg)   formulas+=(ripgrep) ;;
          nvim) formulas+=(neovim)  ;;
          *)    formulas+=("$m")    ;;
        esac
      done
      printf '    Install with Homebrew:\n      brew install %s\n' "${formulas[*]}"
    else
      printf '    Install them via your package manager.\n'
    fi
  fi

  check_nerd_font
  macos_terminal_reminder
  check_starship_shell_init
  printf '    Optional: install the himalaya CLI if you use the himalaya-vim plugin.\n'
}

main() {
  log "Installing dotfiles from $SCRIPT_DIR"
  link_path "$NVIM_SRC" "$NVIM_DST" "neovim config"
  link_path "$TMUX_SRC" "$TMUX_DST" "tmux config"
  link_path "$STARSHIP_SRC" "$STARSHIP_DST" "starship config"
  check_deps

  if (( LINK_CONFLICTS > 0 )); then
    warn "Finished with $LINK_CONFLICTS symlink conflict(s). Resolve them and re-run."
    exit 1
  fi

  if (( DEP_WARNINGS > 0 )); then
    log "Symlinks ready, but install the missing tools above before launching nvim."
  else
    log "Done."
  fi
  printf '    Next: launch %snvim%s — lazy.nvim bootstraps and installs plugins on first run.\n' "$C_OK" "$C_RST"
}

main "$@"
