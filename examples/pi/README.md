# pi in Manuscript

A parity port of the core of the [pi coding agent](https://github.com/badlogic/pi-mono) as a medium-sized Manuscript proof application. It uses only the standard library and is **not meant to merge**: it exists to find language and stdlib gaps.

```sh
ms run examples/pi -- -p "summarize README.md"
ANTHROPIC_API_KEY=... ms run examples/pi          # interactive
ms test examples/pi/src/tools_test.ms
```

Offline testing: `ms run examples/pi/mock -- 127.0.0.1:8099` starts a scripted Anthropic/OpenAI-compatible SSE server; point `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` at it and prompt `bash:CMD`, `write:PATH|TEXT`, `edit:PATH|OLD|NEW` or `read:PATH`.

## Layout

| File | Role |
| --- | --- |
| `src/main.ms` | CLI (`@std/cli/command`), modes, `@file` expansion |
| `src/agent.ms` | Turn loop: stream, run tools, feed results back |
| `src/provider.ms` | Anthropic Messages and OpenAI chat-completions streaming over SSE |
| `src/tools.ms` | read, write, edit, bash, grep, find, ls with output truncation |
| `src/session.ms` | JSONL sessions under `~/.pi/agent/sessions/`, continue/resume |
| `src/prompt.ms` | System prompt, AGENTS.md / CLAUDE.md context files |
| `src/tui.ms` | Raw-mode line editor, streamed output, slash commands |

## Parity with pi

Done: print mode (`-p`), piped stdin, interactive mode with line editing and history, streaming text, tool calls (read, write, edit, bash, grep, find, ls), session save/continue (`-c`, `--session`, `--no-session`), project context files, `--provider anthropic|openai`, `--model`, `--base-url`, `--api-key`, `--tools`, `--no-tools`, `--system-prompt`, `--append-system-prompt`, slash commands `/help /exit /session /tools /usage`.

Missing versus pi: differential full-screen TUI with markdown rendering, image input, extended thinking, OAuth login and model registry (other providers), `/compact` and branching sessions, Esc to abort a running turn, extensions/skills/prompt templates, RPC and JSON modes.
