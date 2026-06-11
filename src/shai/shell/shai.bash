# shai bash integration
# Source this file in your ~/.bashrc:
#   source "$(shai --shell-path bash)"
# or manually:
#   source /path/to/shai/shell/shai.bash

if [ "$(uname)" = "Darwin" ]; then
    _shai_context_file="${XDG_CACHE_HOME:-$HOME/Library/Caches}/shai/context"
else
    _shai_context_file="${XDG_CACHE_HOME:-$HOME/.cache}/shai/context"
fi

# Capture terminal context after each command.
# Uses tmux if available (captures real screen output including stderr).
# Falls back to saving the last command from history.
_shai_save_context() {
    local exit_code=$?
    mkdir -p "$(dirname "$_shai_context_file")"

    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')

    # Don't overwrite context when the last command was shai itself —
    # keep the previous command's context so 'shai help' sees the real output.
    case "$last_cmd" in
        shai*) return $exit_code ;;
    esac

    local _shai_fallback=0
    if [ -n "$TMUX" ]; then
        # tmux: capture last 200 lines of pane scrollback (includes stdout+stderr)
        local target_pane=""
        [ -n "$TMUX_PANE" ] && target_pane="-t $TMUX_PANE"
        if ! tmux capture-pane $target_pane -p -S -200 2>/dev/null > "$_shai_context_file" || [ ! -s "$_shai_context_file" ]; then
            _shai_fallback=1
        fi
    else
        _shai_fallback=1
    fi

    if [ "$_shai_fallback" -eq 1 ]; then
        # No tmux or capture failed: save last command + exit code as minimal context
        {
            echo "$ ${last_cmd}"
            if [ "$exit_code" -ne 0 ]; then
                echo "[exited with code $exit_code]"
            fi
        } > "$_shai_context_file"
    fi
    return $exit_code
}

# Prepend to PROMPT_COMMAND (idempotent)
if [[ "$PROMPT_COMMAND" != *"_shai_save_context"* ]]; then
    PROMPT_COMMAND="_shai_save_context${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
