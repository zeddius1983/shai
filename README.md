# shai — Shell AI

![Built with AI assistance](https://img.shields.io/badge/Built%20with-AI%20assistance-blueviolet?logo=openai&logoColor=white)

LLM-powered assistant for your terminal. Get contextual help from your local or cloud LLM based on what just happened in your shell — errors, failed commands, unexpected output.

Inspired by [PEEL](https://github.com/lemonade-sdk/peel) for PowerShell.

```
$ git pull-request
git: 'pull-request' is not a git command. See 'git --help'.

$ shai help
The command `git pull-request` is not valid. Use `git pull` to fetch and
merge, or install the `gh` CLI and run `gh pr create` to open a pull request.
```

---

## How it works

Shell hooks (`PROMPT_COMMAND` / `precmd`) save your terminal's scrollback after every command. When you run `shai help`, the saved context is sent to your LLM of choice. No copy-pasting, no switching windows.

With tmux, the full screen output (including stderr) is captured. Without tmux, the last command and exit code are saved as fallback.

---

## Installation

### Method 1: Shai Toolbox (Recommended for macOS/Linux)

Shai works out of the box in any terminal, but we provide a cross-platform, idempotent **installer** to perfectly configure your environment with shai and its shell integration (including implicit mode).

Instead of installing things manually, run the installer directly from GitHub:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh)"
```

This installs `shai` and configures `shai implicit mode` by default.

> **Note:** Whenever `~/.zshrc` is modified by the installer, a backup is automatically created first as `~/.zshrc.YYYYMMDD_HHMMSS.bak`.

### Method 2: pipx (Standalone)

```bash
pipx install shai
```

Then add shell integration manually — add one of the following to your shell RC file:

```zsh
# ~/.zshrc
source "$(shai --shell-path zsh)"
```

```bash
# ~/.bashrc
source "$(shai --shell-path bash)"
```

### Method 3: Docker (No Python required)

```bash
docker pull ghcr.io/zeddius1983/shell-assistant:latest
```

Add to `~/.zshrc` or `~/.bashrc`:

```bash
export SHAI_IMAGE="ghcr.io/zeddius1983/shell-assistant:latest"
source /path/to/shell-assistant/shell/shai-docker.sh
```

### Method 4: Build from source

```bash
git clone https://github.com/zeddius1983/shell-assistant
cd shell-assistant
uv tool install .
```

---

## Uninstallation

If you installed via the **Shai Toolbox** (Method 1), you can cleanly uninstall both `shai` and its implicit mode setup by running:
```bash
curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh | bash -s -- --uninstall
```

If you installed via **pipx** (Method 2):
```bash
pipx uninstall shai
```
And manually remove the `source "$(shai --shell-path zsh)"` line from your `~/.zshrc`.

---

## Usage

### Implicit Mode (Ctrl+Space)

If you enabled `[x] shai implicit mode` in the Shai Toolbox installer, you can type any question directly into your terminal and press `Ctrl+Space`:

```bash
find the largest file in this folder[Press Ctrl+Space]
# Instantly expands and runs: shai find the largest file in this folder
```

### Standard Commands

```bash
# Explain what just went wrong
shai help

# Ask anything shell-related
shai how to list all datasets in a ZFS pool
shai what does SIGKILL mean
shai how do I find which process is using port 8080

# Let shai do it — generates a command, shows it, asks before running
shai do find the largest file in ~/Downloads
shai do show disk usage by folder in /var
shai do list all listening ports

# Tip: quote the task if it contains apostrophes or special characters
shai do "show all files modified in the last week"
shai do "find the largest file and show it's size in MB"

# Pipe output directly (no shell hook needed)
kubectl get pods 2>&1 | shai
journalctl -xe | shai why is nginx failing

# Skip context, ask a clean question
shai --no-context explain the difference between hard and soft links

# Raw output — no glow or rich rendering
shai --raw how do I list open ports
shai -r help

# Use a specific provider or model for one query
shai -p anthropic help
shai -p openai -m gpt-4o how do I list listening ports
```

### Subcommands

| Command | Description |
|---|---|
| `shai help` | Analyse your last terminal output and explain errors |
| `shai do <task>` | Generate a shell command, preview it, confirm before running |
| `shai /config` | Show the active config file, or create a default one |
| `shai /context` | Show the full system prompt and captured terminal context |
| `shai /stats` | Show provider, model, context size, and system info |

### Flags

| Flag | Short | Description |
|---|---|---|
| `--no-context` | | Skip attaching terminal context |
| `--raw` | `-r` | Disable glow and rich rendering, stream plain text |
| `--provider <name>` | `-p` | Override the active provider for this query |
| `--model <name>` | `-m` | Override the model for this query |

---

## Configuration

Generate the default config file:
```bash
shai /config
```

This creates `~/.config/shai/config.yaml`:

```yaml
provider: lmstudio        # active provider

providers:
  lmstudio:               # LM Studio (or any OpenAI-compatible local server)
    type: openai
    base_url: http://localhost:1234/v1
    api_key: lmstudio
    model: google/gemma-3-4b

  ollama:
    type: openai
    base_url: http://localhost:11434/v1
    api_key: ollama
    model: llama3.2

  openai:
    type: openai
    model: gpt-4o
    api_key: sk-...       # or set OPENAI_API_KEY env var

  anthropic:
    type: anthropic
    model: claude-sonnet-4-6
    api_key: sk-ant-...   # or set ANTHROPIC_API_KEY env var

  # Any OpenAI-compatible endpoint (vLLM, llama.cpp, etc.)
  custom:
    type: openai
    base_url: http://myserver:8080/v1
    api_key: none
    model: my-model
```

---

## Supported providers

| Provider | `type` | Notes |
|---|---|---|
| [LM Studio](https://lmstudio.ai) | `openai` | Default. Set `base_url: http://localhost:1234/v1` |
| [Ollama](https://ollama.com) | `openai` | Set `base_url: http://localhost:11434/v1` |
| [OpenAI](https://platform.openai.com) | `openai` | Set `OPENAI_API_KEY` |
| [Anthropic](https://anthropic.com) | `anthropic` | Set `ANTHROPIC_API_KEY` |
| llama.cpp / vLLM / any OpenAI-compatible | `openai` | Set `base_url` to your server |

> **Docker note:** `localhost` in your config is automatically rewritten to `host.docker.internal` when shai runs inside a container, so local servers are always reachable.

---

## Development

```bash
git clone https://github.com/zeddius1983/shell-assistant
cd shell-assistant

# Install dev environment
uv sync

# Run directly without installing
.venv/bin/shai --help

# Build a wheel
uv build
# → dist/shai-0.1.0-py3-none-any.whl
```

### Publishing to PyPI

```bash
uv build
uv publish
```

### Publishing to GitHub Container Registry

Push to `main` or create a version tag — the included GitHub Actions workflow builds and pushes automatically:

```bash
git tag v0.1.0
git push origin v0.1.0
# → ghcr.io/zeddius1983/shell-assistant:0.1.0 and :latest
```
