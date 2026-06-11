import os
import yaml
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

CONFIG_PATH = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "shai" / "config.yaml"

def _cache_dir() -> Path:
    if os.environ.get("XDG_CACHE_HOME"):
        return Path(os.environ["XDG_CACHE_HOME"]) / "shai"
    if os.uname().sysname == "Darwin":
        return Path.home() / "Library" / "Caches" / "shai"
    return Path.home() / ".cache" / "shai"

CONTEXT_FILE = _cache_dir() / "context"

DEFAULT_CONFIG = {
    "provider": "lmstudio",
    "context_lines": 100,
    "providers": {
        "lmstudio": {
            "type": "openai",
            "base_url": "http://localhost:1234/v1",
            "api_key": "lmstudio",
            "model": "google/gemma-3-4b",
        },
        "ollama": {
            "type": "openai",
            "base_url": "http://localhost:11434/v1",
            "api_key": "ollama",
            "model": "llama3.2",
        },
        "openai": {
            "type": "openai",
            "model": "gpt-4o",
            # api_key: set via OPENAI_API_KEY env var or here
        },
        "anthropic": {
            "type": "anthropic",
            "model": "claude-sonnet-4-6",
            # api_key: set via ANTHROPIC_API_KEY env var or here
        },
    },
}

SYSTEM_PROMPT = """You are shai, a concise shell assistant embedded in the user's terminal.

## Formatting rules (always follow these)
- Always respond in well-structured Markdown.
- Use `inline code` for command names, flags, paths, and values.
- Use fenced code blocks with language tags for all commands and code:
  ```bash
  your command here
  ```
- Use **bold** for the most important action or fix.
- Use bullet lists for multiple steps or options.
- Keep responses short — no padding, no filler sentences.

## Behaviour
When given terminal context (error analysis mode):
- Look for errors, non-zero exit codes, or unexpected output.
- Lead with the **fix**, then a one-line explanation.
- If there is no error, say so in one sentence and stop.
- Ignore file contents printed by commands like `cat` — focus on command results only.

When asked a question (no context):
- Answer directly and concisely using the formatting rules above."""

DO_SYSTEM_PROMPT = """You are shai, a shell command assistant. The user wants you to perform a task on their system.

Your response must follow this exact structure:
1. One or two sentences explaining what the command will do.
2. Exactly one ```bash code block containing the complete command to execute.
3. Nothing after the code block.

Rules:
- Use a single command, pipe chain, or steps joined with && — keep it one block.
- Prefer safe, non-destructive commands. Avoid `sudo` unless the task requires it.
- Do not add warnings or disclaimers — the user will review the command before it runs.
- CRITICAL: Tailor every command to the user's OS shown in the system info below.
  If OS is macOS:
    * FORBIDDEN: `find -printf` → use `find -exec stat -f '%z %N' {} +` instead
    * FORBIDDEN: `ps aux --sort` → use `ps aux | sort -k4 -rn` instead
    * FORBIDDEN: `stat --format` → use `stat -f` instead
    * FORBIDDEN: `sed -i 's/x/y/'` → use `sed -i '' 's/x/y/'` instead
    * Use `brew` for package installation, not `apt` or `dnf`
  If OS is Linux: GNU tools are available, use them freely."""


@dataclass
class ProviderConfig:
    type: str          # "openai" | "anthropic"
    model: str
    api_key: Optional[str] = None
    base_url: Optional[str] = None


@dataclass
class Config:
    provider: str
    providers: dict
    context_lines: int = 100
    system_prompt: str = SYSTEM_PROMPT

    def get_active_provider(self) -> ProviderConfig:
        if self.provider not in self.providers:
            raise ValueError(
                f"Provider '{self.provider}' not found in config. "
                f"Available: {list(self.providers.keys())}"
            )
        raw = self.providers[self.provider]
        return ProviderConfig(
            type=raw.get("type", "openai"),
            model=raw["model"],
            api_key=raw.get("api_key"),
            base_url=raw.get("base_url"),
        )


def load_config() -> Config:
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            data = yaml.safe_load(f) or {}
    else:
        data = {}

    # Deep merge with defaults
    merged = dict(DEFAULT_CONFIG)
    merged.update({k: v for k, v in data.items() if k != "providers"})

    providers = dict(DEFAULT_CONFIG["providers"])
    providers.update(data.get("providers", {}))
    merged["providers"] = providers

    return Config(
        provider=merged["provider"],
        providers=merged["providers"],
        context_lines=merged.get("context_lines", 100),
        system_prompt=merged.get("system_prompt", SYSTEM_PROMPT),
    )


def save_default_config():
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        yaml.dump(DEFAULT_CONFIG, f, default_flow_style=False, sort_keys=False)
    return CONFIG_PATH
