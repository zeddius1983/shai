#!/usr/bin/env bash
# Shai installer
#
# Usage:
#   Interactive (pick what to install):
#     ./shell/setup.sh
#
#   Silent — install everything:
#     ./shell/setup.sh --all
#     SETUP_SILENT=1 bash ./shell/setup.sh
#
#   Uninstall:
#     ./shell/setup.sh --uninstall
#
#   Via curl:
#     curl -fsSL https://raw.githubusercontent.com/zeddius1983/shai/main/install.sh | bash
#     curl -fsSL https://raw.githubusercontent.com/zeddius1983/shai/main/install.sh | bash -s -- --uninstall

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
  sed "/# -- shai-toolbox: ${key} --/,/# -- end shai-toolbox: ${key} --/d" "$ZSHRC" > "$tmp"
  mv "$tmp" "$ZSHRC"
  info "Removed $key from ~/.zshrc"
}

# ---------------------------------------------------------------------------
# Install functions
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
      printf "  %s " "$(cyan "Enter keybinding for shai implicit mode [default: ^@ (Ctrl+Space)]:")"
      read -r bind </dev/tty
    fi
    [ -z "$bind" ] && bind="^@"
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
# Interactive menu (pure POSIX shell — no whiptail/dialog needed)
# ---------------------------------------------------------------------------

# Menu entries: "key|label|description" OR "H|Header Title"
MENU_ENTRIES=(
  "H|🧠 Shai"
  "shai|shai|AI shell assistant"
  "shai-implicit|shai implicit mode|Run shai on current buffer with custom hotkey"
)

_show_menu() {
  local n=${#MENU_ENTRIES[@]}
  local i=0
  while [ $i -lt $n ]; do
    local type="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f1)"
    if [ "$type" = "H" ]; then
      eval "selected_$i=-1"
    else
      if _zshrc_has "$type"; then eval "selected_$i=1"
      else eval "selected_$i=0"; fi
    fi
    i=$((i + 1))
  done

  local cursor=0
  while [ $cursor -lt $n ]; do
    local sel; eval "sel=\$selected_$cursor"
    if [ "$sel" -ne -1 ]; then break; fi
    cursor=$((cursor + 1))
  done

  local TTY=/dev/tty
  tput civis 2>/dev/null >&"$TTY" || true
  local old_stty
  old_stty="$(stty -g 2>/dev/null < "$TTY" || echo '')"
  stty -echo -icanon min 1 time 0 < "$TTY" 2>&1 || true

  _menu_render() {
    printf '\033[%dA' "$((n + 2))" > "$TTY" 2>/dev/null || true
    local j=0
    while [ $j -lt $n ]; do
      local type label desc sel check
      type="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f1)"
      eval "sel=\$selected_$j"
      if [ "$type" = "H" ]; then
        label="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f2)"
        if [ -z "$label" ]; then
          printf '\033[2K\r\n' > "$TTY"
        else
          printf '\033[2K\r  %s\n' "$(bold "$(cyan "$label")")" > "$TTY"
        fi
      else
        label="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f2)"
        desc="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f3)"
        if [ "$j" -eq "$cursor" ]; then
          if [ "$sel" -eq 1 ]; then
            check="$(cyan '❯') $(green '◉')"
            label="$(cyan "$(bold "$label")")"
          else
            check="$(cyan '❯') $(dim '◯')"
            label="$(cyan "$(bold "$label")")"
          fi
        else
          if [ "$sel" -eq 1 ]; then
            check="  $(green '◉')"
          else
            check="  $(dim '◯')"
          fi
        fi
        printf '\033[2K\r %s  %s  %s  %s\n' "$check" "$label" "$(dim '—')" "$(dim "$desc")" > "$TTY"
      fi
      j=$((j + 1))
    done
    printf '\033[2K\r\n\033[2K\r  %s\n' "$(dim 'SPACE toggle · ENTER confirm · a select all · n deselect all · q quit')" > "$TTY"
  }

  printf '\n  %s\n' "$(bold 'Shai Setup')" > "$TTY"
  printf '  %s\n\n' "$(dim '──────────────────────────────────────')" > "$TTY"

  seq 1 $((n + 2)) | while read -r _; do printf '\n' > "$TTY"; done
  _menu_render

  while true; do
    local char
    IFS= read -r -s -n1 char < "$TTY" || true

    if [ "$char" = $'\x1b' ]; then
      IFS= read -r -s -n1 -t 0.1 char2 < "$TTY" || true
      if [ "$char2" = '[' ]; then
        IFS= read -r -s -n1 -t 0.1 char3 < "$TTY" || true
        case "$char3" in
          A)
            local tmp=$cursor
            while [ $tmp -gt 0 ]; do
              tmp=$((tmp - 1))
              local sel; eval "sel=\$selected_$tmp"
              if [ "$sel" -ne -1 ]; then cursor=$tmp; break; fi
            done
            ;;
          B)
            local tmp=$cursor
            while [ $tmp -lt $((n - 1)) ]; do
              tmp=$((tmp + 1))
              local sel; eval "sel=\$selected_$tmp"
              if [ "$sel" -ne -1 ]; then cursor=$tmp; break; fi
            done
            ;;
        esac
      fi
    elif [ "$char" = ' ' ]; then
      local cur_sel
      eval "cur_sel=\$selected_$cursor"
      if [ "$cur_sel" -ne -1 ]; then eval "selected_$cursor=$(( 1 - cur_sel ))"; fi
    elif [ "$char" = 'a' ]; then
      local k=0; while [ $k -lt $n ]; do local s; eval "s=\$selected_$k"; [ "$s" -ne -1 ] && eval "selected_$k=1"; k=$((k+1)); done
    elif [ "$char" = 'n' ]; then
      local k=0; while [ $k -lt $n ]; do local s; eval "s=\$selected_$k"; [ "$s" -ne -1 ] && eval "selected_$k=0"; k=$((k+1)); done
    elif [ "$char" = $'\r' ] || [ "$char" = $'\n' ] || [ "$char" = '' ]; then
      break
    elif [ "$char" = 'q' ]; then
      stty "$old_stty" < "$TTY" 2>&1 || true
      tput cnorm 2>/dev/null > "$TTY" || true
      printf '\n\nAborted.\n' > "$TTY"
      exit 0
    fi
    _menu_render
  done

  stty "$old_stty" < "$TTY" 2>&1 || true
  tput cnorm 2>/dev/null > "$TTY" || true
  printf '\n' > "$TTY"

  local k=0
  while [ $k -lt $n ]; do
    local sel type
    eval "sel=\$selected_$k"
    type="$(echo "${MENU_ENTRIES[$k]}" | cut -d'|' -f1)"
    if [ "$sel" -eq 1 ] && [ "$type" != "H" ]; then
      echo "$type"
    fi
    k=$((k + 1))
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {

  local silent=0 uninstall=0
  for arg in "$@"; do
    case "$arg" in
      --all|-a)    silent=1 ;;
      --uninstall) uninstall=1 ;;
    esac
  done
  [ "${SETUP_SILENT:-0}" = "1" ] && silent=1

  touch "$ZSHRC"

  local to_install=""

  local n=${#MENU_ENTRIES[@]}
  local i=0
  while [ $i -lt $n ]; do
    local type="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f1)"
    if [ "$type" = "H" ]; then
      i=$((i + 1))
      continue
    fi
    if _zshrc_has "$type"; then
      eval "INITIAL_STATE_$(echo "$type" | tr '-' '_')=1"
    else
      eval "INITIAL_STATE_$(echo "$type" | tr '-' '_')=0"
    fi
    i=$((i + 1))
  done

  if [ "$uninstall" -eq 1 ]; then
    info "$(yellow "Uninstall mode: removing all installed shai components...")"
    to_install=""
  elif [ "$silent" -eq 1 ]; then
    info "$(yellow "Silent mode: installing all components")"
    to_install="shai shai-implicit"
  else
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      warn "No TTY detected (running via pipe?). Switching to --all mode."
      to_install="shai shai-implicit"
    else
      local _menu_tmp
      _menu_tmp="$(mktemp)"
      _show_menu > "$_menu_tmp"
      to_install="$(cat "$_menu_tmp")"
      rm -f "$_menu_tmp"
    fi
  fi

  i=0
  while [ $i -lt $n ]; do
    local type="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f1)"
    if [ "$type" = "H" ]; then
      i=$((i + 1))
      continue
    fi
    local key="$type"
    local safe_key
    safe_key="$(echo "$key" | tr '-' '_')"

    local was_installed
    eval "was_installed=\$INITIAL_STATE_$safe_key"

    local is_selected=0
    for comp in $to_install; do
      if [ "$comp" = "$key" ]; then is_selected=1; break; fi
    done

    if [ "$was_installed" -eq 0 ] && [ "$is_selected" -eq 1 ]; then
      "install_$safe_key"
    elif [ "$was_installed" -eq 1 ] && [ "$is_selected" -eq 0 ]; then
      "uninstall_$safe_key"
    fi

    i=$((i + 1))
  done

  printf '\n%s\n\n' "$(green "$(bold '✓ All done!')")"
  printf 'Reload your shell to apply changes:\n'
  printf '  %s\n\n' "$(bold "source $ZSHRC")"
}

main "$@"
