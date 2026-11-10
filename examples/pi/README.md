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

Done: print, json and rpc modes; piped stdin; markdown output; extended thinking; image input; tools read, write, edit, bash, grep, find, ls; Esc or Ctrl-C aborts a turn including a running command; session tree (`/tree`, `/fork`), `/compact`, `-c`, `--session`, `--no-session`, `/new`; context files; nine built-in providers (Anthropic, OpenAI, OpenRouter, Groq, xAI, Mistral, Cerebras, Gemini, Ollama), custom providers from pi's own `~/.pi/agent/models.json`, keys from the environment, `~/.pi/agent/auth.json` or `/login`, `--list-models`, `provider/model` names; skills (`SKILL.md` directories, listed in the system prompt); prompt templates (`~/.pi/agent/prompts/*.md`, `$1`, `$@`); tool extensions (`~/.pi/agent/extensions/*.json`, a command that reads the call's JSON on stdin); an in-place multi-line editor (wrapping, footer, diffed redraw, word editing, history, Tab completion, Alt-Enter, paste heuristic).

Differences from pi: no OAuth login (API keys only; a browser flow needs more than the stdlib offers); extensions are external commands, not TypeScript modules; no Google-native or Bedrock wire formats (Gemini is used through its OpenAI-compatible endpoint); Shift-Enter and real paste events are not available from the terminal API (see issue #3517); rpc has no `abort` command and no image input; a stalled stream cannot be aborted until the next event (#3516).
