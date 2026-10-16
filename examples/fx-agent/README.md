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

Typed JSON encoding and decoding now make protocol code safer. This example
serializes its model request and decodes each tool's arguments directly as
records, eliminating manual field and kind checks for shapes it owns. The
remaining dynamic JSON code handles provider responses: typed record decoding
rejects unknown members, while OpenAI-compatible providers can add metadata the
agent does not consume. The planned custom `JsonDecode` hook or an explicit
unknown-member policy would let that boundary become typed without making it
brittle. Tool-schema construction also remains verbose because property names
are dynamic JSON object keys.

The standard library has improved since the first version of this example. It
now includes incremental JSON and SSE decoders, managed subprocesses with live
pipes and process-group cleanup, and scoped raw-terminal input with resize and
cursor operations. These APIs remove the largest systems-integration blockers
for streaming providers, MCP servers, and interactive clients. Read-only
accessors also make collection and optional queries shorter, although migrating
the example from method spellings required a mechanical source update. The
compiler identified each obsolete call and its replacement precisely.

A reusable permission/tool abstraction would still let applications state
policy separately from command execution instead of mixing prompts with tool
handlers.

The language's small core is pleasant here: ordinary functions cover waiting,
callbacks, and the loop without async syntax. I would preserve that. The best
remaining improvement is tolerant/custom typed decoding for evolving external
protocols rather than new control-flow syntax.

