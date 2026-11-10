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
| `src/main.ms` | CLI (`@std/cli/command`), modes (text, json, rpc), slash commands, `@file` and image expansion |
| `src/agent.ms` | Turn loop, abort, `/compact`, `/fork` |
| `src/provider.ms` | Anthropic Messages and OpenAI chat-completions streaming over SSE, thinking, images |
| `src/tools.ms` | read, write, edit, bash, grep, find, ls with output truncation; bash is cancellable |
| `src/session.ms` | JSONL session tree (id and parent per entry), compaction entries, continue/resume |
| `src/prompt.ms` | System prompt, AGENTS.md / CLAUDE.md context files |
| `src/ui.ms`, `src/frontends.ms` | The `Ui` interface and its terminal, plain and JSON-lines implementations |
| `src/markdown.ms` | Streaming markdown to ANSI |
| `src/tui.ms` | Raw-mode line editor (history, Tab completion, Alt-Enter newline), Esc/Ctrl-C abort |

## Parity with pi

Done: print, json and rpc modes; piped stdin; interactive mode with line editing, history, markdown output and streamed text; extended thinking (`--thinking`, `/thinking`); image input (`@image.png`); tools read, write, edit, bash, grep, find, ls; Esc or Ctrl-C aborts a running turn (including a running bash command); sessions as a tree (`/tree`, `/fork`), `/compact` with compaction entries, `-c`, `--session`, `--no-session`, `/new`; project context files; `--provider anthropic|openai`, `--model`, `--base-url`, `--api-key`, `--tools`, `--no-tools`, `--system-prompt`, `--append-system-prompt`; slash commands `/help /exit /session /tools /usage /model /thinking /compact /tree /fork /new`.

Differences from pi: output is append-only scrollback with a line editor, not a differentially redrawn component tree; no paste or Shift-Enter handling; no OAuth login or model registry (two providers); no extensions, skills or prompt templates; rpc has no `abort` command while a prompt runs; images in rpc prompts are not accepted.
