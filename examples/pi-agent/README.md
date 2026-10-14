# Pi core agent in Manuscript

A native Manuscript implementation of the provider-independent Pi agent core,
modeled on [`packages/agent`](https://github.com/earendil-works/pi/tree/9fe3f371622cad9cc1a3cbf044288abd0252192f/packages/agent)
at upstream revision `9fe3f371622cad9cc1a3cbf044288abd0252192f`.
All agent behavior lives in `.ms` source and compiles to a standalone executable.
It does not invoke Pi, Node.js, TypeScript, or another agent process.
The upstream MIT notice is retained in [LICENSE.pi](LICENSE.pi).

## Run it

From the Manuscript repository root, build the compiler once with `make build`,
then:

```sh
./ms check examples/pi-agent/ms.toml
./ms lock examples/pi-agent/ms.toml
./ms run examples/pi-agent/ms.toml
./ms test examples/pi-agent/src/test.ms --timeout 20s
./ms build examples/pi-agent/ms.toml -o /tmp/pi-agent
/tmp/pi-agent
```

The demo uses an in-process model fixture: it requests an echo tool, receives its
result, and completes. Expected output:

```text
Say hello
Hello from a native Manuscript tool
Done.
```

`ms lock` records the current compiler and native toolchain pins. Refresh it when
those change. In an environment with a read-only home, set `XDG_CACHE_HOME` to a
writable directory for `ms`; set `GOCACHE` and `GOPATH` for `make build`.

## Use the core

Import [agent.ms](src/agent.ms) and [types.ms](src/types.ms) into a Manuscript
project. `create_agent` takes a `Config` and optional initial `Context`, copying
the outer message and tool lists. Seed the prompt with `Message(Role.System, ...)`
and send user messages through `prompt`. `continue_agent` retries an existing
transcript without returning its old messages; it rejects empty history and an
assistant as the last message. `run_agent_loop` and `run_agent_loop_continue`
provide entrypoints without retaining an Agent value.

`Config.stream` is the model boundary. It receives a `Request` containing the
transcript, available tools, model identifier, and thinking level. It calls
`update` with partial assistant snapshots and returns `Result[Message, Error]`
with the final assistant message. The core records that final message, dispatches
its tool calls, appends results, and requests another model turn until finished.
Provider failures become failed assistant messages and a failed run Result;
the final `AgentEnd` still arrives. A provider returning another role is rejected.

A `Tool` declares its name, description, JSON parameters, validator, and executor.
`validate` returns normalized arguments or a typed error before execution.
`execute` receives the call, cancellation control, and an update callback. Unknown
tools, invalid arguments, hook failures, and executor errors become model-facing
error results. The executor can also return `ToolResult(is_error: true)`.
Calls from a length-limited response produce error results without execution.
`run_tool_call` uses the same validation and hooks for tools invoking other tools,
without writing events or transcript messages.

Tool batches default to parallel execution with `TaskGroup`. Validation and the
before hook run in source order before tasks start. Tool completion events follow
completion order; tool-result messages follow assistant source order. A sequential
configuration or any tool's sequential override makes the whole batch sequential.
The event sink and after hooks are serialized. `terminate` ends a run only when
every result in the batch requests it; `finish_turn` can end or ensure one more
request independently.

`steer` and `follow_up` enqueue messages through synchronized control. Steering
is drained before the first request and after tool batches; follow-ups wait until
the agent would otherwise stop. Queue modes select all messages or one at a time.
Steering never skips already requested tool calls. `finish_turn: End` leaves
queued work untouched. `abort` sets a cooperative token; callbacks must poll
`is_aborted(control)` and stop their own work. It does not interrupt arbitrary
blocking I/O. `reset` clears history and queues while idle and retains the model,
tools, and subscriptions.

`Config.emit` receives typed agent, turn, message, and tool events. `subscribe`
adds a listener and returns an unsubscribe function. Calls are ordinary Manuscript
functions and settle before processing continues; the agent remains busy during
`AgentEnd` callbacks. Partial model and tool updates after their callback's return
are ignored. State includes the current partial assistant and pending tool IDs.

`transform_context` and `convert_to_llm` run at the model boundary, leaving the
stored transcript's outer list intact. `prepare_request` runs before every
request; `prepare_next_turn` runs only if another turn is scheduled. These hooks
may replace context, model, and thinking level. `finish_turn` receives the final
assistant, tool results, current context, and newly produced messages.

### Callback and sharing contracts

Own an Agent on one task. Enqueueing and cancellation may come from other tasks;
changing its configuration, context, subscriptions, or starting a second run
from another task requires caller synchronization. Listeners must not mutate
active configuration or transcript during a parallel batch. They may enqueue,
abort, or unsubscribe. Callbacks must return expected failures through Result;
programming faults are Manuscript faults and are not caught as tool errors.

Copies are shallow. Treat handed-off message snapshots and JSON payloads as
read-only, or clone their mutable contents before changing them. Tools protect
their own shared data. No agent lock is held while executing a tool. Update and
event callbacks must not wait for the provider/tool task that invoked them.

## Scope and native adaptations

This implements the core conversation/tool loop and stateful Agent. The coding
agent CLI, filesystem/bash tools, TUI, session storage, compaction, extension
loading, skills, proxy transport, authentication, and provider SDKs are outside
this example. The demo is deterministic; a live model needs a Manuscript callback
implementing the `stream` contract.

The API follows Manuscript's contracts rather than claiming TypeScript wire/API
compatibility:

- Ordinary functions and `TaskGroup` replace Promises and async iterators. Streams
  deliver typed snapshots through callbacks; block-level provider delta events
  can be interpreted inside an adapter.
- Explicit alternatives replace discriminated structural unions. Custom message
  declaration merging is omitted with extension support.
- JSON arguments use `JsonValue`. A per-tool validator replaces TypeBox; no
  general JSON Schema engine is bundled. The schema remains available to the
  model adapter.
- System prompts are ordinary system messages; tool declarations are provided
  through `Request.context.tools`. Pi's transcript tool-change protocol and
  system-section normalization belong to its `pi-ai` boundary and are not
  reproduced here. An adapter must translate these into its provider's format.
- Model IDs and thinking levels are strings. Provider-specific model catalogs,
  usage accounting, timestamps, replay policy, and HTTP options are not part of
  this provider-independent API.
- After hooks return a whole `ToolResult`, including structured content, rather
  than an untyped partial object merge. Tools retain structured output in
  completion events; only model-facing content and details enter the transcript.
- Cancellation is an explicit synchronized token. Run results use Result;
  programming faults retain their native meaning.

## Validation

The 20 tests in [test.ms](src/test.ms) exercise ordered transcripts, actual parallel
overlap and completion order, both queue modes, continuation, busy-state checks,
reset, provider failures, cooperative abort, invalid/unknown/failed tools,
truncation, blocking/termination hooks, request transforms, explicit continuation,
subscription settlement, late-update suppression, and argument normalization.

`make examples-check` checks these actual modules through
[TestPiAgent](../../tests/examples/pi_agent_test.go). The repository's native
coverage mode also runs their behavioral tests and checks the demo's output:

```sh
MANUSCRIPT_EXAMPLES_NATIVE=1 toolchain/go/bin/go test ./tests/examples -run '^TestPiAgent$' -count=1
```

The generated test executable also passed all 20 tests when built with Go's
race detector; no races were reported.

See [language notes](LANGUAGE_NOTES.md) for observations from this port.
