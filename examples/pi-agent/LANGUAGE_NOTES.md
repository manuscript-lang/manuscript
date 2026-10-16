# Language observations from porting Pi

These observations compare the native core with Pi's TypeScript implementation
at `9fe3f371622cad9cc1a3cbf044288abd0252192f`. They describe this checkout's
behavior, not proposed language features as though they already exist.

| TypeScript/Pi | Manuscript port | What I like / opportunity |
| --- | --- | --- |
| `async`, Promise, `Promise.all` | Ordinary functions and `TaskGroup` with `Task[ToolResult]` | I like having one function kind. Parallel work and its joined lifetime are explicit at the batch boundary. Typed task results require more collection/unwrap code. |
| Thrown tool/provider errors | `Result[T, Error]`, flat match and `try` | I like seeing the expected failure contract at each boundary. Programming faults remain separate. Adapters must consciously translate operational failures into Result. |
| Discriminated union objects | `Content`, `Role`, `Event`, `StopReason` alternatives | Exhaustive matching makes lifecycle handling reviewable. Optional fields on a shared Message record still permit invalid role/field combinations; distinct message variants could improve this application API. |
| TypeBox schema plus inferred parameters | `JsonValue`, automatic schema validation, and optional native validators | The untrusted boundary is visible. Completing the port required a source validator with coercion, references, constraints and format predicates. A reusable JSON Schema library would remove this application-level work without adding syntax. |
| Structural interfaces and partial hook overrides | Nominal records, typed callbacks, and ToolResultPatch | Explicit Optional fields express omission without `unknown` or object spreads. Content replacement deliberately drops stale structured output; that behavior belongs in the finalization pipeline. |
| Closure sharing in an event-loop application | Shared references with explicit `Synchronized` guards | The control queue and tool-event gate show exactly where sharing is protected. Read-only callback contracts still rely on discipline because exported record fields and nested payloads are mutable. |
| Array indexing returns an element (possibly undefined) | List indexing returns `Optional[T]` | Absence cannot disappear. Inside a proven in-range `entries()` loop, repeated `.unwrap()` is noisy; stronger tooling explanations or an indexed iteration API could help. |
| Positional arguments are unambiguous | Unlabeled arguments bind by position; explicit labels select by name | Issue #452 is now fixed on main. A bare identifier can no longer redirect an argument by spelling. Explicit `stream:`/`emit:` labels remain useful when skipping defaulted fields. |
| Async iterators deliver stream events | A provider callback delivers typed partial snapshots | Less runtime machinery is needed, and consumers settle before the next step. The standard BlockingQueue now supplies waiting, buffering and backpressure for adapters that need decoupled consumption. |
| AbortSignal shared through callbacks | A synchronized cooperative control token and an owned HTTP client | The proxy can interrupt a blocked request/read by closing its owned client. Guard wait/notify now removes watcher polling. The watcher still closes the owned client to interrupt HTTP; a reusable cancellation handle could compose directly with native waits. |
| Fluent APIs and direct object methods | Exported functions operating on Agent records | Dependencies and operations remain clear. Source record methods require an explicit interface implementation, so functions avoid a ceremonial interface created only for method syntax. |

The compiler caught callback-label mismatches and missing Optional extraction
before native execution. The same source could then be checked, formatted,
compiled, and tested with one CLI. That is a strong fit for agent-authored ports.
The current formatter keeps imports and callbacks compact within 88 columns,
addressing the expansion observed during the initial port.

The most useful remaining improvements are libraries: reusable JSON Schema
validation and cancellation handles that compose directly with native operations.
This port required no compiler, syntax, standard-library, or runtime changes.

## What completing the core taught us

**Use lexical lifetime to settle application state.** `RunSettlement` implements
Closeable and clears busy/pending/partial state on return, typed-error propagation
and programming-fault unwinding. `UpdateLifetime` similarly revokes saved provider
and tool update callbacks when their operation faults. This replaced normal-path
cleanup assumptions with source-level scopes. The fault tests distinguish both
state settlement and late-callback suppression; neither requires changing native
faults into ordinary Results.

**Concentrate synchronization at actual task boundaries.** TypeScript's event-loop
callbacks did not require the cross-thread event gate needed by parallel native
tools. That gate protects completion events and after hooks; Control protects
cross-task enqueue, abort and run settlement. Race-free execution alone does not
justify guarding all application state. A BlockingQueue with one state-owning
consumer remains an alternative architecture; the separate Queue stays local and
nonblocking. This port now uses guard `wait()`/`notify_all()` for idle settlement
and cancellation, removing both 1 ms polling loops without adding an owner task.
The cancellation watcher remains necessary to close the HTTP client.

**Snapshots need deliberate storage boundaries.** `.clone()` is shallow. The
validator deep-copies JSON before preparation/normalization; transcript declarations
copy schemas; partial proxy snapshots copy their content-list and signature-map
storage. Callbacks still receive nested references and must treat them as read-only.
The new read-only accessors expose live values, not immutable object graphs, so
they do not remove this snapshot requirement. Typed JSON is now available, while
the existing JsonValue stringify/parse bridge still supplies a deliberate deep copy.

**Opaque payloads affect the entire alternative's equality.** Adding a cancellation
handle to ToolCall meant Event no longer derived Equal, including comparisons to
the payloadless AgentStart case. Matching `AgentStart:` is the appropriate way to
inspect its tag. Do not invent equality for resource handles just to keep a
convenience comparison compiling.

**Use explicit host values for shared configuration.** Module-level `let` values
are use-site constants, not a mutable process registry. A StreamRuntime supplied
to Config lets several agents share a default stream deliberately and permits
independent hosts. Record defaults create fresh runtimes; sharing requires passing
the same value. This preserves Manuscript's visible-dependency direction.

**Read signatures instead of assuming familiar spellings.** Float parsing is
`parse_float` from `@std/numbers.ms`; String's parse helper is `parse_int`.
ResponseBody and ReadStream are distinct contracts, so the proxy supplies a small
explicit adapter. A view is `ReadStream(value)`, not `value as ReadStream`.
Import renaming has no syntax. Callback parameter labels remain part of function
identity, including inside Optional. The compiler caught these mistakes before
native execution. Opportunities are better discoverability and composable APIs,
not automatically adding every construct another language provides.

The indexing and call-binding observations are tracked in
[#451](https://github.com/manuscript-lang/manuscript/issues/451) and
[#452](https://github.com/manuscript-lang/manuscript/issues/452). Issue #452 is
resolved by positional binding on main; #451 remains an indexing design observation. This port does not change either language rule.

Finally, native feature coverage and TypeScript identity are different claims.
The completed scheduling tests distinguish initial listener steering, failed-turn
hooks, terminated batches with queued input, and preparation-message events.
Native HTTP tests distinguish parser correctness from actually interrupting a
blocked read. The README records the schema-engine and native API boundaries;
test counts alone are not a substitute for checking upstream contracts.

Run completion identity and cancellation identity also need separate treatment.
Queues and idle-wait generations live in shared orchestration state, while each
run receives a fresh cancellation control. Reusing one mutable abort flag resets
signals retained by earlier callers. The native regression keeps an aborted token,
starts a successful second run, and checks that the old token remains aborted.
When choosing defaults, remember that `unwrap_or(default)` evaluates its fallback
eagerly; conditional extraction avoids allocating an unused synchronization object.
