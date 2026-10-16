# fx agent in Manuscript

This example is a native Manuscript coding-agent binary inspired by
[`vercel-labs/fx`](https://github.com/vercel-labs/fx). It implements the core
model/tool loop against an OpenAI-compatible Chat Completions endpoint.

```sh
export FX_API_KEY=...
export FX_MODEL=gpt-4.1-mini
ms run ms.toml -- "inspect this project and fix the failing test"
```

Configuration is supplied through the environment:

- `FX_BASE_URL` defaults to `https://api.openai.com/v1/chat/completions`.
- `FX_MODEL` defaults to `gpt-4.1-mini`.
- `FX_PERMISSION` is `ask`, `auto`, or `full-access` and defaults to `ask`.
  `auto` permits reads and asks before shell commands or writes.
- `FX_MAX_STEPS` defaults to 32.
- `FX_SESSION` defaults to `.fx-manuscript-session.jsonl`.
- `FX_CONTINUE=1` resumes the transcript at `FX_SESSION`.

The binary reads `AGENTS.md` from the working directory, gives the model
`read_file`, `write_file`, `list_files`, `search`, `shell`, `web_fetch`, and
`delegate` tools, bounds tool output and model responses, saves the conversation
after each tool batch, and supports either a prompt argument or a line read from
standard input. `delegate` runs a focused model turn as a subagent.

## Parity with fx

The implementation corresponds to the native `fx ask` workflow: a configurable
OpenAI-compatible provider and model, iterative function calls, workspace
instructions, filesystem/indexed-search/command/web tools, permission modes,
bounded execution, delegated investigation, inline terminal output, and durable
resumable transcripts. It builds through Manuscript's normal native pipeline,
so the result is a standalone executable.

## Language notes from the port

Manuscript's strongest fit is the application boundary. Native HTTP, JSON,
filesystem, process, byte streams, explicit `Result` values, and lexical `with`
cleanup make the request/tool loop compact and its resource lifetime visible.
The same source becomes a native executable without a package/runtime install.
Alternative types and exhaustive `match` also make protocol decoding easier to
audit than unchecked object access.

The main friction is dynamic protocol work. Extracting fields from `JsonValue`
is repetitive, and the lack of a concise object literal makes request/schema
construction visually heavy. A typed JSON decoding facility, or derived codecs
for records and alternatives, would remove much of that code while retaining
explicit failures. Streaming HTTP responses also need an SSE parser in source;
a standard incremental event-stream decoder would help agents and other CLI
clients. Finally, a reusable permission/tool abstraction would let applications
state policy separately from command execution instead of mixing prompts with
tool handlers.

The language's small core is pleasant here: ordinary functions cover waiting,
callbacks, and the loop without async syntax. I would preserve that. The best
improvement opportunity is library-level protocol ergonomics, especially typed
JSON and streaming codecs, rather than new language syntax.

