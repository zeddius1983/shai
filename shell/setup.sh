#!/usr/bin/env bash
# Shai Installer — idempotent setup script for shai and shell integrations
#
# Usage:
#   Interactive:
#     ./shell/setup.sh
#
#   Uninstall:
#     ./shell/setup.sh --uninstall
#
#   Silent / Non-interactive:
#     ./shell/setup.sh --all

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours & output helpers
# ---------------------------------------------------------------------------

bold()    { printf '\033[1m%s\033[0m' "$*"; }
green()   { printf '\033[32m%s\033[0m' "$*"; }
yellow()  { printf '\033[33m%s\033[0m' "$*"; }
red()     { printf '\033[31m%s\033[0m' "$*"; }
cyan()    { printf '\033[36m%s\033[0m' "$*"; }
dim()     { printf '\033[2m%s\033[0m' "$*"; }

step()  { printf '\n%s %s\n' "$(bold '==>')" "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s\n' "$(green "✓ $*")"; }
warn()  { printf '    %s\n' "$(yellow "Warning: $*")"; }
die()   { printf '\n%s %s\n\n' "$(red 'Error:')" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

OS=""
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  *) die "Unsupported OS: $(uname -s)" ;;
esac

# ---------------------------------------------------------------------------
# .zshrc idempotent patching
# ---------------------------------------------------------------------------

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
_ZSHRC_BACKED_UP=0

_backup_zshrc() {
  if [ "$_ZSHRC_BACKED_UP" -eq 1 ]; then return; fi
  if [ -f "$ZSHRC" ]; then
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp -p "$ZSHRC" "$ZSHRC.$ts.bak"
    info "Created backup: $ZSHRC.$ts.bak"
  fi
  _ZSHRC_BACKED_UP=1
}

_zshrc_has() { grep -qF "shai-toolbox: $1" "$ZSHRC" 2>/dev/null; }

_zshrc_add() {
  local key="$1"; shift
  if _zshrc_has "$key"; then
    info "$(dim "~/.zshrc[$key] already present — skipping")"
    return
  fi
  _backup_zshrc
  {
    printf '\n# -- shai-toolbox: %s --\n' "$key"
    printf '%s\n' "$@"
    printf '# -- end shai-toolbox: %s --\n' "$key"
  } >> "$ZSHRC"
  info "Added $key to ~/.zshrc"
}

_zshrc_remove() {
  local key="$1"
  if ! _zshrc_has "$key"; then return; fi
  _backup_zshrc
  local tmp
  tmp="$(mktemp)"
  # Delete lines from start marker to end marker inclusive
  sed "/# -- shai-toolbox: ${key} --/,/# -- end shai-toolbox: ${key} --/d" "$ZSHRC" > "$tmp"
  mv "$tmp" "$ZSHRC"
  info "Removed $key from ~/.zshrc"
}

# ---------------------------------------------------------------------------
# Install/Uninstall core functions
# ---------------------------------------------------------------------------

install_shai() {
  step "Installing shai..."
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi
  uv tool install "git+https://github.com/zeddius1983/shell-assistant.git" --force --refresh
  export PATH="$(uv tool dir 2>/dev/null | sed 's|/tools$|/bin|'):$HOME/.local/bin:$PATH"
  
  local _shai_path
  _shai_path="$(command shai --shell-path zsh 2>/dev/null | xargs)"
  if [ -z "$_shai_path" ]; then
    warn "Could not determine shai shell integration path — add manually: source \"\$(shai --shell-path zsh)\""
  else
    _zshrc_add "shai" "source \"$_shai_path\""
  fi
  ok "shai installed"
}

uninstall_shai() {
  step "Uninstalling shai..."
  uv tool uninstall shai 2>/dev/null || true
  _zshrc_remove "shai"
  ok "shai uninstalled"
}

install_shai_implicit() {
  local bind="${SHAI_IMPLICIT_BIND:-}"
  if [ -z "$bind" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      printf "  %s " "$(cyan "Enter keybinding for shai implicit mode [default: \\es (Alt+s)]:")"
      read -r bind </dev/tty
    fi
    [ -z "$bind" ] && bind="\es"
  fi

  step "Installing shai implicit mode (binding: $bind)..."
  _zshrc_add "shai-implicit" \
    "function _shai_implicit_mode() {" \
    "  if [[ -n \"\${BUFFER}\" ]]; then" \
    "    BUFFER=\"shai \${BUFFER}\"" \
    "    CURSOR=\${#BUFFER}" \
    "    zle accept-line" \
    "  fi" \
    "}" \
    "zle -N _shai_implicit_mode" \
    "bindkey '$bind' _shai_implicit_mode"
  ok "shai implicit mode installed"
}

uninstall_shai_implicit() {
  step "Uninstalling shai implicit mode..."
  _zshrc_remove "shai-implicit"
  ok "shai implicit mode uninstalled"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local mode="install"
  local silent=0

  for arg in "$@"; do
    case "$arg" in
      --uninstall|-u) mode="uninstall" ;;
      --all|-a) silent=1 ;;
    esac
  done
  [ "${SETUP_SILENT:-0}" = "1" ] && silent=1

  # Touch ~/.zshrc if not present
  touch "$ZSHRC"

  if [ "$mode" = "uninstall" ]; then
    uninstall_shai_implicit
    uninstall_shai
    printf '\n%s\n\n' "$(green "$(bold '✓ Uninstallation complete!')")"
    return 0
  fi

  # Install shai core
  install_shai

  # Determine if we should install shai-implicit
  local install_implicit=0
  if [ "$silent" -eq 1 ]; then
    install_implicit=1
  else
    if [ -t 0 ] && [ -t 1 ]; then
      printf "  %s " "$(cyan "Do you want to install shai implicit mode (hotkey-based shell runner)? [y/N]:")"
      local answer
      read -r answer </dev/tty
      case "$answer" in
        [yY][eE][sS]|[yY]) install_implicit=1 ;;
      esac
    fi
  fi

  if [ "$install_implicit" -eq 1 ]; then
    install_shai_implicit
  else
    uninstall_shai_implicit
  fi

  printf '\n%s\n\n' "$(green "$(bold '✓ All done!')")"
  printf 'Reload your shell to apply changes:\n'
  printf '  %s\n\n' "$(bold "source $ZSHRC")"
}

main "$@"
