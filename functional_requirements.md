# Functional Requirements: shai (Shell AI)

`shai` is an LLM-powered command-line assistant designed to help developers and system administrators directly inside their terminal. It acts as an interactive assistant that is context-aware of recent terminal activity, enabling users to troubleshoot errors, ask shell-related questions, and generate/execute commands safely.

---

## 1. Context-Aware Terminal Assistance

`shai` automatically analyzes recent terminal scrollback and activity to provide context-appropriate explanations and solutions without requiring manual copy-pasting.

*   **Error Analysis & Troubleshooting:** When invoked after a command fails, `shai` automatically detects errors, non-zero exit codes, and unexpected stdout/stderr outputs to suggest immediate, bolded fixes.
*   **Terminal Multiplexer Integration:** When running inside `tmux`, `shai` captures the full scrollback of the active pane (up to a configurable limit) to ensure it has exact stdout/stderr logs.
*   **Fallback Hook System:** When not running within a terminal multiplexer, `shai` captures the last executed command and its exit status.
*   **History Fallback:** As a final recovery, `shai` falls back to reading the most recent shell history entries to infer what the user was working on.
*   **Piped Input Support:** Users can pipe outputs, error logs, or command results directly into `shai` (e.g., `command 2>&1 | shai`) for immediate analysis.

---

## 2. Natural Language Command Execution (`do` mode)

`shai` allows users to translate natural language tasks into terminal commands, preview them, edit them, and run them interactively.

*   **Interactive Preview:** Displays the suggested command with full syntax highlighting inside a terminal panel.
*   **Safety Alerts:** Displays warnings if a generated command contains potentially destructive actions (e.g., recursive deletions, filesystem modification commands, or system privilege elevation like `sudo`).
*   **Compatibility Warnings:** Warns the user if a command uses GNU-specific syntax on platforms where only BSD utilities are standard (e.g., macOS).
*   **Inline Editing:** Allows the user to edit the generated command directly in the shell input buffer before executing.
*   **Interactive Confirmation:** Prompts the user with a confirmation prompt (`Run? [Y/n/e]`) before executing any generated command on the host.

---

## 3. Shell Integration & Implicit Mode

`shai` integrates into the user's active shell session to streamline workflows.

*   **Implicit Mode (Hotkey Expansion):** Users can type any question or task directly in the shell command prompt and press a hotkey (defaulting to `Ctrl+Space`). The shell automatically prefixes the input with the `shai` command and executes it immediately.
*   **Environment Setup & Uninstall Menu:** A terminal-based user interface allows users to easily install, configure, or clean up all shell integrations.

---

## 4. Diagnostics & Information

`shai` provides subcommands to inspect the state, configuration, and variables that influence the assistant's behavior.

*   **Prompt & Context Inspection:** Users can run a diagnostic subcommand to preview the complete system prompt and the exact terminal scrollback context that is sent to the LLM.
*   **Statistics & Environment Info:** Users can view active LLM settings (provider, model, endpoints), current context statistics (captured lines, estimated tokens), and local system specifications.
*   **System Detail Autopopulation:** Automatically detects host system specifications (operating system version, CPU architecture, memory capacity, active shell, and available package managers) and attaches them to queries so generated commands are tailored to the environment.

---

## 5. Configuration & LLM Providers

`shai` is fully customizable and works with local, offline, and cloud-based language models.

*   **Configuration Subcommand:** Initializes and prints the path and contents of the configuration file.
*   **Multi-Provider Integration:** Supports multiple backends:
    *   **Local Servers:** Connects to local AI servers (such as LM Studio and Ollama).
    *   **Cloud Providers:** Integrates with OpenAI and Anthropic platforms.
    *   **Custom Endpoints:** Compatible with any custom server exposing a standard API interface.

---

## 6. Execution Control & Override Flags

Users can customize the behavior of any `shai` query using flags:

*   **Context Suppression:** Option to completely disable attaching recent terminal scrollback.
*   **Formatting Control:** Option to request raw, unformatted text streams to bypass Markdown formatting.
*   **Model/Provider Override:** Option to specify a different model or provider on a per-command basis.
