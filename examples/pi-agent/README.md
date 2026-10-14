# Pi core agent in Manuscript

A native Manuscript implementation of the provider-independent Pi core at
[`9fe3f371622cad9cc1a3cbf044288abd0252192f`](https://github.com/earendil-works/pi/tree/9fe3f371622cad9cc1a3cbf044288abd0252192f/packages/agent).
The agent, transcript replay, JSON argument validator, and HTTP streaming proxy
are `.ms` source compiled into native executables. They do not invoke Pi, Node.js,
TypeScript, or another agent process. The upstream notice is in [LICENSE.pi](LICENSE.pi).

## Run it

Build the Manuscript CLI once with `make build`, then run from the repository root:

```sh
./ms check examples/pi-agent/ms.toml
./ms lock examples/pi-agent/ms.toml
./ms run examples/pi-agent/ms.toml
./ms test examples/pi-agent/src/test.ms --timeout 20s
./ms build examples/pi-agent/ms.toml -o /tmp/pi-agent
/tmp/pi-agent
```

The deterministic demo asks an in-process model fixture to call an echo tool:

```text
Say hello
Hello from a native Manuscript tool
Done.
```

Refresh `ms.lock` when compiler/toolchain pins change. For a read-only home, set
`XDG_CACHE_HOME` for `ms` and `GOCACHE`/`GOPATH` for Go/Make to writable directories.

## Agent and scheduling

Import [agent.ms](src/agent.ms) and [types.ms](src/types.ms).
`create_agent(config, context)` copies the outer history/tool lists and seeds a
system tool baseline when starting with tools and history has no leading system message. Supply system
messages to seed the prompt. Use `prompt` for message batches, `prompt_message`
for one message, or `prompt_text` for text with optional image blocks.

`continue_agent` retries user/tool-result history. After an assistant, it first
consumes queued steering, then follow-ups, without double-draining a
one-at-a-time batch. It rejects empty or system-only history. Low-level
`run_agent_loop` and `run_agent_loop_continue` return only newly produced
messages; their less restrictive input checks match the low-level Pi loop.
Their outer input history is copied rather than modified.

`steer` queues mid-run input; `follow_up` waits until the agent would otherwise
stop. Each queue can drain all messages or one at a time. Steering queued by
initial turn/message listeners reaches the first request. A terminated tool
batch still considers queues and explicit continuation. `finish_turn: End`
ends immediately without consuming queued work. Failed and aborted responses
call the finish hook but remain hard exits regardless of its decision.

`prepare_request` runs before each model request. `prepare_next_turn` runs only
when another turn is scheduled; its returned `Request.messages` are appended
with normal message lifecycle events. Steering arriving during preparation is
picked up without double-draining an existing batch. Model/thinking changes
persist for later requests and runs. Context transformation and model conversion
operate on a copied outer list, leaving durable history intact.

Queue management includes `peek_queued_messages`, `has_queued_messages`, and
independent steering/follow-up/all clearing functions. Peek returns a copy of
the next selected batch, giving steering priority. `set_tools` and
`replace_messages` copy outer lists; `append_message` adds idle history.
`get_system_prompt` replays system text and sections. `reset` preserves the
replayed system prompt/tool baseline and clears conversation, queues and errors.

## Model boundary and lifecycle

`Config.stream` receives a `Request`, synchronized control, and a partial-message
callback, returning `Result[Message, Error]`. Operational failures become failed
assistant messages and a failed run Result, with turn/agent end events. Invalid
final roles are rejected. Message metadata carries model/provider/API, timestamps,
thinking levels, token/cost usage, content signatures, and tool duration.

For a default stream, create a `StreamRuntime`, install a callback through
`set_default_stream_fn`, and pass it as `Config.runtime`. An explicitly supplied
stream takes precedence. This runtime is an explicit host value; separate hosts
can have different defaults. Clearing it causes an ordinary missing-stream error. Configure shared runtimes
before starting work, or synchronize changes when multiple hosts use one.

`Config.options` carries provider stream options, including session, transport,
headers, metadata, sampling, cache and retry settings. `get_api_key` resolves a
fresh key before each request, falling back to the configured key for an empty
resolution. Provider adapters receive payload/response/raw-event hooks through
Request; raw events can also arrive as `Event.ProviderUpdate`.

`Config.emit` and `subscribe` deliver typed lifecycle events sequentially.
Subscription returns an unsubscribe function. The agent remains busy until
`AgentEnd` listeners settle. `active_signal` exposes control only during a run;
`abort` is an idle no-op and otherwise requests cooperative cancellation.
Callbacks receive a fresh cancellation control for each run; old tokens retain
their aborted state after later runs start. Enqueue through the Agent queue APIs.
`wait_for_idle` waits for the run observed on entry, including listener
settlement, even if another run subsequently begins.

Scoped `Closeable` lifetimes settle run state and revoke saved update callbacks
on both normal exits and programming faults. Expected failures use Result;
programming faults remain native faults and are not silently converted into
ordinary tool failures. Ordinary functions may suspend, so callers can use
`TaskGroup` to run an agent alongside a UI or other work.

## Tools and validation

A Tool declares its schema and executor. The core prepares arguments, validates
and coerces JSON according to the schema, and runs any additional native validator
before the permission hook. Any rewritten arguments are checked again against
the declared schema. `ToolCall.arguments` contains validated arguments;
`original_arguments`, `assistant_message`, and `control` supply hook context.
Unknown tools, validation/permission failures and executor errors become
model-facing error results. Length-limited tool arguments never execute.

The validator supports primitive/union types, enum/const, object properties,
required/additional/pattern properties, property-name and dependent-required
checks, arrays/tuples, item/count/uniqueness/contains constraints, string/numeric
constraints, conjunction/disjunction/negation/conditionals, and local object
JSON-pointer references. Optional non-nullable null properties are removed;
primitive coercion follows Pi's JSON-schema boundary. Input is deep-copied.

Built-in formats cover date/time, regex, URI, email, UUID, hostname and IPv4.
`Tool.formats` supplies predicates for application-specific formats.
Validation rejects unsupported assertions, formats, external references and
nesting above 128 rather than skipping constraints. Patterns use Manuscript's
RE2 engine. This is a native tool-schema validator, not TypeBox's JavaScript
runtime or a complete implementation of every JSON Schema dialect.

Tool batches default to parallel `TaskGroup` execution. Validation and permission
hooks run in source order; completion events follow finish order, while result
messages follow assistant source order. A sequential configuration or any tool's
sequential override serializes the whole batch. Hooks see a consistent
post-assistant batch context. Sequential cancellation stops admission of the
remaining calls.

`after_tool_call` can replace a whole result. `after_tool_patch` supplies typed
field overrides: omitted values survive; replacing content drops stale structured
output unless the patch supplies it too. Usage and execution timing survive
finalization. `run_tool_call` and `run_tool_call_outcome` use the same pipeline
for explicit tool invocation without adding transcript/events. Output schemas
and replay policies are retained as declarations; like Pi, dispatch does not
perform durable replay or automatically enforce output schemas.
`schema.validate_output` is available for explicit output checking.

## Transcript and proxy

[transcript.ms](src/transcript.ms) replays system text, named-section replacement
and removal, and tool additions/removals. Changed tool definitions emit a removal
followed by an addition. Pending system tool intent is reconciled against the
executable loadout. Declarations omit executors and copy JSON schemas.
`collapse_system_messages` produces a current leading system message for
providers that cannot accept later system messages.

[proxy.ms](src/proxy.ms) provides `stream_proxy(ProxyOptions, Request, control,
update)` for Pi's `/api/stream` protocol. Wrap it in a Config stream callback and
supply the server URL, bearer token and model descriptor. It serializes only the
upstream option whitelist, excluding provider API keys and executable callbacks.

The adapter reconstructs text, thinking, tool-call fragments, signatures, terminal
usage and provider thinking levels from SSE. It handles incomplete tool JSON for
partial display; schema validation still gates execution of final arguments.
Malformed streams and EOF without a terminal event fail. Optional request/body/
event limits and timeouts are honored. Payload/response/raw-event hooks run at
the appropriate boundaries. Each request owns its HTTP client; cancellation
closes it to interrupt a blocked request or body read.

## Ownership and native adaptations

Own mutable Agent state on one task. Cross-task enqueue/abort/idle waiting use
Control; parallel tool event delivery and after hooks use a serialized gate.
Callbacks must treat snapshots, schemas and nested payloads as read-only or clone
them. Tools protect their own shared data. Do not wait for idle inside a run
listener, or join work while holding a guard that work needs.

Manuscript has no blocking channel/condition API in this checkout. Idle waiting
and the proxy cancellation watcher use a suspending 1 ms poll. The proxy's own
HTTP client is closed on cancellation; arbitrary model/tool callbacks remain
responsible for stopping their work. Programming-fault semantics, explicit host
defaults, separate prompt functions, typed patches and copied outer history are
native API choices rather than TypeScript API/exception identity.

The coding-agent CLI, filesystem/bash tools, TUI, session storage, compaction,
extension loading and provider SDK/catalog implementations remain outside this
core port. A direct live provider uses a native callback; the bundled proxy can
connect to a compatible server.

## Validation and language learning

[The native suite](src/test.ms) covers 53 core behavior cases, including scheduling,
transcript replay, schemas, hook context, lifecycle failures, retained callback
revocation, listener settlement and proxy event reconstruction. The generated
suite is also exercised with Go's race detector.

[TestPiAgent and TestPiAgentProxy](../../tests/examples/pi_agent_test.go) check the
actual modules. Native mode runs the suite and demo plus seven real loopback HTTP
cases: successful fragmented Unicode SSE, HTTP error, premature EOF, malformed
JSON, event limits, blocked-read abort and timeout.

```sh
make examples-check repo-check licenses-check
MANUSCRIPT_EXAMPLES_NATIVE=1 toolchain/go/bin/go test ./tests/examples -run '^TestPiAgent' -count=1
```

See [LANGUAGE_NOTES.md](LANGUAGE_NOTES.md) for language observations and remaining
library opportunities. Durable lessons are recorded in the repository experts;
no compiler, syntax, standard-library or runtime change was required.
