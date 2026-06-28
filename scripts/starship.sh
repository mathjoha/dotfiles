#!/usr/bin/env bash
# Starship setup: install binary, wire shell rc, symlink config.
#
# Can be sourced by setup.sh (uses caller's helpers) or run standalone:
#   ./scripts/starship.sh              # install + wire + link config
#   ./scripts/starship.sh --no-config  # install + wire only (no config symlink)
set -euo pipefail

_STARSHIP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helpers (only defined when running standalone) ---
if ! declare -F log >/dev/null 2>&1; then
  if [[ -t 1 ]]; then
    C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_INFO=$'\033[1;34m'; C_RST=$'\033[0m'
  else
    C_OK=''; C_WARN=''; C_INFO=''; C_RST=''
  fi
  log()      { printf '%s==>%s %s\n' "$C_INFO" "$C_RST" "$*"; }
  ok()       { printf '%s ok%s %s\n' "$C_OK" "$C_RST" "$*"; }
  warn()     { printf '%s !!%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
  dep_warn() { warn "$*"; }
fi

# --- Install starship binary ---
install_starship() {
  if command -v starship >/dev/null 2>&1; then
    ok "Starship already installed: $(command -v starship)"
    return
  fi

  log "Installing starship"
  if [[ "$OSTYPE" == darwin* ]] && command -v brew >/dev/null 2>&1; then
    brew install starship
  else
    local bin_dir="/usr/local/bin"
    if [[ ! -w "$bin_dir" ]]; then
      bin_dir="$HOME/.local/bin"
      mkdir -p "$bin_dir"
    fi
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y --bin-dir "$bin_dir"
    # Ensure ~/.local/bin is on PATH for the rest of this script
    if [[ "$bin_dir" == "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$bin_dir:"* ]]; then
      export PATH="$bin_dir:$PATH"
    fi
  fi

  if command -v starship >/dev/null 2>&1; then
    ok "Starship installed: $(command -v starship)"
  else
    dep_warn "Starship installation failed"
  fi
}

# --- Wire starship init into the shell rc ---
wire_starship_shell_init() {
  local shell_name="${SHELL##*/}"
  local init_line
  local rcfile

  case "$shell_name" in
    zsh)
      init_line='eval "$(starship init zsh)"'
      rcfile="$HOME/.zshrc"
      ;;
    bash)
      init_line='eval "$(starship init bash)"'
      rcfile="$HOME/.bashrc"
      ;;
    fish)
      init_line='starship init fish | source'
      rcfile="$HOME/.config/fish/config.fish"
      ;;
    *)
      dep_warn "Unknown shell ($SHELL) — wire up starship init manually."
      printf '    https://starship.rs/#step-2-set-up-your-shell-to-use-starship\n'
      return 0
      ;;
  esac

  if [[ -f "$rcfile" ]] && grep -q 'starship init' "$rcfile" 2>/dev/null; then
    ok "Starship shell init already in $rcfile"
    return 0
  fi

  # Create rc file if missing, append init line
  mkdir -p "$(dirname "$rcfile")"
  printf '\n# Starship prompt\n%s\n' "$init_line" >> "$rcfile"
  ok "Starship shell init added to $rcfile"
}

# --- Symlink starship config ---
link_starship_config() {
  local src="$_STARSHIP_SCRIPT_DIR/../starship/starship.toml"
  local dst="$HOME/.config/starship.toml"

  # Resolve to absolute path
  src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

  if [[ ! -f "$src" ]]; then
    warn "Starship config not found: $src"
    return 1
  fi

  # If setup.sh's link_path is available, use it (handles conflicts properly)
  if declare -F link_path >/dev/null 2>&1; then
    link_path "$src" "$dst" "starship config"
    return
  fi

  # Standalone: simple symlink logic
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    ok "starship config already linked: $dst -> $src"
    return
  fi

  if [[ -e "$dst" ]]; then
    warn "starship config: $dst already exists. Back it up, then re-run."
    return 1
  fi

  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  ok "starship config linked: $dst -> $src"
}

# --- Main (only when run directly, not sourced) ---
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  link_config=1
  for arg in "$@"; do
    case "$arg" in
      --no-config) link_config=0 ;;
    esac
  done

  log "Setting up starship"
  install_starship
  wire_starship_shell_init
  if (( link_config )); then
    link_starship_config
  fi
  log "Done."
fi
