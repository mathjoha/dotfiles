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

# LazyVim (main branch) requires a recent Neovim. apt's neovim on Ubuntu LTS is
# usually too old, so we version-gate and point at the upstream release tarball.
NVIM_MIN_VERSION="0.11.2"

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

# True (0) if version $1 is strictly less than version $2.
version_lt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

# Print copy-pasteable steps to install the latest Neovim release into ~/.local
# (no root). On macOS, defer to Homebrew.
neovim_release_hint() {
  if [[ "$OSTYPE" == darwin* ]]; then
    printf '    Install/upgrade Neovim with Homebrew:\n      brew install neovim\n'
    return
  fi

  local asset
  case "$(uname -m)" in
    x86_64|amd64)  asset="nvim-linux-x86_64.tar.gz" ;;
    aarch64|arm64) asset="nvim-linux-arm64.tar.gz"  ;;
    *)             asset="" ;;
  esac

  if [[ -z "$asset" ]]; then
    printf '    Grab a recent Neovim from https://github.com/neovim/neovim/releases/latest\n'
    return
  fi

  printf '    apt'\''s Neovim is too old for LazyVim; install the latest release into ~/.local:\n'
  printf '      mkdir -p ~/.local/opt ~/.local/bin\n'
  printf '      curl -fsSL https://github.com/neovim/neovim/releases/latest/download/%s | tar -xz -C ~/.local/opt\n' "$asset"
  printf '      ln -sf ~/.local/opt/%s/bin/nvim ~/.local/bin/nvim\n' "${asset%.tar.gz}"
  printf '    (ensure ~/.local/bin is on PATH, e.g. in ~/.bashrc).\n'
}

# Warn if an installed Neovim is older than LazyVim's floor.
check_nvim_version() {
  command -v nvim >/dev/null 2>&1 || return 0
  local have
  have="$(nvim --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
  [[ -n "$have" ]] || return 0
  if version_lt "$have" "$NVIM_MIN_VERSION"; then
    dep_warn "Neovim $have is too old — LazyVim needs >= $NVIM_MIN_VERSION."
    neovim_release_hint
  fi
}

# Login shells (SSH, console, `bash -l`) do NOT read ~/.bashrc on their own —
# they read the first of ~/.bash_profile, ~/.bash_login, ~/.profile that exists.
# Ubuntu often ships only ~/.bashrc, so PATH/prompt set there never load at login
# (and check_starship_shell_init would falsely report "ok"). Make a login profile
# source ~/.bashrc. bash-only: zsh/fish have different login-file semantics.
check_login_sources_bashrc() {
  [[ "${SHELL##*/}" == bash ]] || return 0
  [[ -f "$HOME/.bashrc" ]] || return 0

  # bash reads the FIRST of these that exists, then stops looking.
  local profile="" f
  for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [[ -f "$f" ]]; then profile="$f"; break; fi
  done

  if [[ -n "$profile" ]]; then
    if grep -q 'bashrc' "$profile" 2>/dev/null; then
      ok "Login shells source ~/.bashrc (via $profile)"
    else
      # A login profile exists but ignores ~/.bashrc — don't edit it for them.
      dep_warn "Login profile $profile does not source ~/.bashrc; login shells skip it."
      printf '    Add this line to %s:\n' "$profile"
      printf '      [ -f ~/.bashrc ] && . ~/.bashrc\n'
    fi
    return 0
  fi

  # No login profile at all — safe to create one (mirrors link_path: only act
  # when nothing is there to clobber).
  local dst="$HOME/.bash_profile"
  cat > "$dst" <<'EOF'
# ~/.bash_profile — sourced by login shells (SSH, console, `bash -l`).
# Interactive non-login shells read ~/.bashrc directly; login shells do not,
# so pull it in here to keep one source of truth for PATH, prompt, etc.
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
  ok "Created $dst so login shells source ~/.bashrc"
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
    elif command -v apt-get >/dev/null 2>&1; then
      # On Debian/Ubuntu the apt package names differ from the binary names:
      #   rg -> ripgrep    fd -> fd-find
      # nvim is handled separately: apt's neovim is too old for LazyVim.
      local pkgs=()
      local fd_renamed=0
      local nvim_missing=0
      for m in "${missing[@]}"; do
        case "$m" in
          rg)   pkgs+=(ripgrep) ;;
          fd)   pkgs+=(fd-find); fd_renamed=1 ;;
          nvim) nvim_missing=1  ;;
          *)    pkgs+=("$m")    ;;
        esac
      done
      if (( ${#pkgs[@]} )); then
        printf '    Install with apt (packages live in the "universe" component):\n'
        printf '      sudo apt install %s\n' "${pkgs[*]}"
      fi
      if (( nvim_missing )); then
        neovim_release_hint
      fi
      if (( fd_renamed )); then
        # fd-find installs the binary as "fdfind" to avoid a clash with an old
        # "fd" package, so expose it under the name our tooling expects.
        printf '    Note: fd-find installs the binary as %sfdfind%s, not %sfd%s.\n' "$C_WARN" "$C_RST" "$C_WARN" "$C_RST"
        printf '    Symlink it onto your PATH:\n'
        printf '      mkdir -p ~/.local/bin && ln -sf "$(command -v fdfind)" ~/.local/bin/fd\n'
        printf '    (ensure ~/.local/bin is on PATH, e.g. in ~/.bashrc).\n'
      fi
    else
      printf '    Install them via your package manager.\n'
    fi
  fi

  check_nvim_version
  check_nerd_font
  macos_terminal_reminder
  check_login_sources_bashrc
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
