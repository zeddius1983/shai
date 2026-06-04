# shai Docker integration for zsh
# No Python required — shai runs inside Docker.
#
# Usage: add to ~/.zshrc:
#   source /path/to/shai-docker.zsh
#
# Optional: set image name (default: ghcr.io/youruser/shai:latest)
#   export SHAI_IMAGE="ghcr.io/youruser/shai:latest"

# Only load in zsh
[ -n "$ZSH_VERSION" ] || return 0

# On macOS, Docker Desktop only mounts $HOME by default — avoid /tmp
if [[ "$(uname)" == "Darwin" ]]; then
    _shai_cache_dir="$HOME/Library/Caches/shai"
else
    _shai_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/shai"
fi
_shai_context_file="$_shai_cache_dir/context"
_shai_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shai"
SHAI_IMAGE="${SHAI_IMAGE:-ghcr.io/youruser/shai:latest}"

# Hook: save terminal context after every command
_shai_save_context() {
    local exit_code=$?
    mkdir -p "$(dirname "$_shai_context_file")"

    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')

    local _cmd_name="${SHAI_CMD_NAME:-shai}"
    case "$last_cmd" in
        "$_cmd_name"*) return $exit_code ;;
    esac

    local _shai_fallback=0
    if [ -n "$TMUX" ]; then
        local target_pane=""
        [ -n "$TMUX_PANE" ] && target_pane="-t $TMUX_PANE"
        if ! tmux capture-pane $target_pane -p -S -200 2>/dev/null > "$_shai_context_file" || [ ! -s "$_shai_context_file" ]; then
            _shai_fallback=1
        fi
    else
        _shai_fallback=1
    fi

    if [ "$_shai_fallback" -eq 1 ]; then
        {
            echo "$ ${last_cmd}"
            [ "$exit_code" -ne 0 ] && echo "[exited with code $exit_code]"
        } > "$_shai_context_file"
    fi
    return $exit_code
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _shai_save_context

# shai wrapper: delegates to Docker container
_shai_docker_wrapper() {
    mkdir -p "$_shai_config_dir" "$(dirname "$_shai_context_file")"

    local _container_bin="docker"
    if ! command -v docker >/dev/null 2>&1; then
        if command -v podman >/dev/null 2>&1; then
            _container_bin="podman"
        else
            echo "Error: Neither docker nor podman was found in PATH." >&2
            return 1
        fi
    fi

    local _tty_flags=()
    [ -t 0 ] && _tty_flags+=(-i)
    [ -t 1 ] && _tty_flags+=(-t)

    "$_container_bin" run --rm "${_tty_flags[@]}" \
        -e OPENAI_API_KEY \
        -e ANTHROPIC_API_KEY \
        -e TERM \
        -e COLORTERM \
        -v "${_shai_config_dir}:/home/shai/.config/shai:ro" \
        -v "${_shai_cache_dir}:/home/shai/.cache/shai:ro" \
        "$SHAI_IMAGE" "$@"
}

SHAI_CMD_NAME="${SHAI_CMD_NAME:-shai}"
eval "${SHAI_CMD_NAME}() { _shai_docker_wrapper \"\$@\"; }"
