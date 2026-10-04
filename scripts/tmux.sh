#!/usr/bin/env bash
# tmux session persistence: install TPM, install plugins headlessly,
# wire persistent shell history (what tmux-resurrect no longer does upstream).
#
# Can be sourced by setup.sh (uses caller's helpers) or run standalone:
#   ./scripts/tmux.sh              # link config + TPM + plugins + history wiring
#   ./scripts/tmux.sh --no-config  # skip the config symlink
set -euo pipefail

_TMUX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# --- Install TPM (tmux plugin manager) ---
install_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"

  if [[ -d "$tpm_dir/.git" ]]; then
    ok "TPM already installed: $tpm_dir"
    return 0
  fi

  log "Installing TPM"
  if ! git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir" 2>/dev/null; then
    dep_warn "TPM clone failed — install manually:"
    printf '      git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm\n'
    return 0
  fi
  ok "TPM installed: $tpm_dir"
}

# --- Install declared plugins without needing prefix+I ---
install_tmux_plugins() {
  local installer="$HOME/.tmux/plugins/tpm/bin/install_plugins"

  if [[ ! -f "$HOME/.tmux.conf" ]]; then
    dep_warn "~/.tmux.conf not found — link it first, then re-run plugin install."
    return 0
  fi
  if [[ ! -x "$installer" ]]; then
    dep_warn "TPM not present — plugins not installed (prefix+I inside tmux also works)."
    return 0
  fi

  # tpm reads TMUX_PLUGIN_MANAGER_PATH from the tmux server's environment,
  # not the shell's — a server started before tpm was in .tmux.conf doesn't
  # have it and the installer aborts. Seed any running server first.
  export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/"
  # Fails harmlessly when no server is running (that case works without it)
  tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TMUX_PLUGIN_MANAGER_PATH" 2>/dev/null || true
  if ! "$installer" >/dev/null 2>&1; then
    dep_warn "TPM headless plugin install failed — press prefix+I inside tmux instead."
    return 0
  fi

  local plugin
  for plugin in tmux-resurrect tmux-continuum; do
    if [[ -d "$HOME/.tmux/plugins/$plugin" ]]; then
      ok "tmux plugin installed: $plugin"
    else
      dep_warn "tmux plugin missing after install: $plugin"
    fi
  done
}

# --- Wire persistent shell history into the shell rc ---
# Restored panes get up-arrow recall: every command is flushed to the history
# file immediately, so history survives reboots alongside resurrect's layout.
wire_history_persistence() {
  local shell_name="${SHELL##*/}"
  local rcfile

  case "$shell_name" in
    zsh)  rcfile="$HOME/.zshrc"  ;;
    bash) rcfile="$HOME/.bashrc" ;;
    fish)
      ok "fish persists history by default — nothing to wire"
      return 0
      ;;
    *)
      dep_warn "Unknown shell ($SHELL) — wire up persistent history manually."
      return 0
      ;;
  esac

  if [[ -f "$rcfile" ]] && grep -q '# Persistent shell history' "$rcfile" 2>/dev/null; then
    ok "Persistent history already in $rcfile"
    return 0
  fi

  mkdir -p "$(dirname "$rcfile")"
  if [[ "$shell_name" == "bash" ]]; then
    cat >> "$rcfile" <<'EOF'

# Persistent shell history
shopt -s histappend
HISTSIZE=100000
HISTFILESIZE=200000
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF
  else
    cat >> "$rcfile" <<'EOF'

# Persistent shell history
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=200000
setopt INC_APPEND_HISTORY
EOF
  fi
  ok "Persistent history added to $rcfile"
}

# --- Symlink tmux config ---
link_tmux_config() {
  local src="$_TMUX_SCRIPT_DIR/../tmux/.tmux.conf"
  local dst="$HOME/.tmux.conf"

  # Resolve to absolute path
  src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

  if [[ ! -f "$src" ]]; then
    warn "tmux config not found: $src"
    return 1
  fi

  # If setup.sh's link_path is available, use it (handles conflicts properly)
  if declare -F link_path >/dev/null 2>&1; then
    link_path "$src" "$dst" "tmux config"
    return
  fi

  # Standalone: simple symlink logic
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    ok "tmux config already linked: $dst -> $src"
    return
  fi

  if [[ -e "$dst" ]]; then
    warn "tmux config: $dst already exists. Back it up, then re-run."
    return 1
  fi

  ln -s "$src" "$dst"
  ok "tmux config linked: $dst -> $src"
}

# --- Main (only when run directly, not sourced) ---
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  link_config=1
  for arg in "$@"; do
    case "$arg" in
      --no-config) link_config=0 ;;
    esac
  done

  log "Setting up tmux session persistence"
  if (( link_config )); then
    link_tmux_config
  fi
  install_tpm
  install_tmux_plugins
  wire_history_persistence
  log "Done."
fi
