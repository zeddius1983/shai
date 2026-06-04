# shai Docker integration for bash
# No Python required — shai runs inside Docker.
#
# Usage: add to ~/.bashrc:
#   source /path/to/shai-docker.bash
#
# Optional: set image name (default: ghcr.io/youruser/shai:latest)
#   export SHAI_IMAGE="ghcr.io/youruser/shai:latest"

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

if [[ "$PROMPT_COMMAND" != *"_shai_save_context"* ]]; then
    PROMPT_COMMAND="_shai_save_context${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

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

    # Check if --raw or -r was passed — only scan leading flags, stop at first non-flag word
    # Also skip glow for /context, /stats and any /subcommand (they output rich ANSI panels)
    local _raw=0
    for _arg in "$@"; do
        case "$_arg" in
            --raw|-r) _raw=1 ;;
            /*)       _raw=1 ; break ;;  # /config, /context, /stats output rich panels, not markdown
            -*) ;;          # other flag, keep scanning
            *) break ;;     # first non-flag word: stop
        esac
    done

    local _cmd=("$_container_bin" run --rm)
    [ -t 0 ] || _cmd+=(-i)
    _cmd+=(
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -v "${_shai_config_dir}:/root/.config/shai:ro"
        -v "${_shai_cache_dir}:/root/.cache/shai:ro"
        "$SHAI_IMAGE"
    )

    if [ "$_raw" -eq 0 ] && command -v glow > /dev/null 2>&1; then
        "${_cmd[@]}" "$@" | glow -
    else
        "${_cmd[@]}" "$@"
    fi
}

SHAI_CMD_NAME="${SHAI_CMD_NAME:-shai}"
eval "${SHAI_CMD_NAME}() { _shai_docker_wrapper \"\$@\"; }"
