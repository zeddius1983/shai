"""
Terminal context capture for shai.

Priority order:
  1. Piped stdin (most explicit)
  2. tmux capture-pane (always current — beats a potentially stale hook file)
  3. Saved context file (written by shell hooks, used when not in tmux)
  4. Shell history fallback (last N history entries)
"""

import os
import select
import stat as stat_module
import subprocess
import sys
from pathlib import Path
from typing import Optional

from .config import CONTEXT_FILE


def get_context(lines: int = 100) -> Optional[str]:
    """Return the best available terminal context string, or None."""
    # 1. Piped stdin — only consume if data is actually available
    if not sys.stdin.isatty() and _stdin_has_data():
        return sys.stdin.read().strip() or None

    # 2. tmux capture — always reflects the current live pane output
    tmux_ctx = _tmux_capture(lines)
    if tmux_ctx:
        return tmux_ctx

    # 3. Saved context file from shell hook (used when not in tmux)
    if CONTEXT_FILE.exists():
        text = CONTEXT_FILE.read_text().strip()
        if text:
            return _last_n_lines(text, lines)

    # 4. Shell history fallback
    return _history_fallback(10)


def _stdin_has_data() -> bool:
    """Return True if stdin is an actual pipe or file with data (not /dev/null or a pty)."""
    try:
        mode = os.fstat(sys.stdin.fileno()).st_mode
        # Only treat as piped input if stdin is a real pipe (FIFO) or regular file
        if not (stat_module.S_ISFIFO(mode) or stat_module.S_ISREG(mode)):
            return False
        return bool(select.select([sys.stdin], [], [], 0)[0])
    except (ValueError, OSError):
        return False


def _last_n_lines(text: str, n: int) -> str:
    lines = text.splitlines()
    return "\n".join(lines[-n:])


def _tmux_capture(lines: int) -> Optional[str]:
    if not os.environ.get("TMUX"):
        return None
    try:
        args = ["tmux", "capture-pane", "-p", "-S", str(-lines)]
        if os.environ.get("TMUX_PANE"):
            args.extend(["-t", os.environ["TMUX_PANE"]])
            
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=3,
        )
        return result.stdout.strip() or None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def _history_fallback(n: int) -> Optional[str]:
    """Read last n entries from $HISTFILE."""
    histfile = os.environ.get("HISTFILE", "")
    if not histfile:
        shell = os.environ.get("SHELL", "")
        if "zsh" in shell:
            histfile = str(Path.home() / ".zsh_history")
        else:
            histfile = str(Path.home() / ".bash_history")

    path = Path(histfile)
    if not path.exists():
        return None

    try:
        # zsh history may use extended format (; lines). Strip those.
        lines = []
        for line in path.read_text(errors="replace").splitlines():
            if line.startswith(":") and line.count(":") >= 2:
                # extended format ": <timestamp>:<elapsed>;<cmd>"
                parts = line.split(";", 1)
                if len(parts) == 2:
                    lines.append("$ " + parts[1])
            elif line.strip():
                lines.append("$ " + line.strip())
        return "\n".join(lines[-n:]) or None
    except OSError:
        return None
