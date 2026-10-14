# Language observations from porting Pi

These observations compare the native core with Pi's TypeScript implementation
at `9fe3f371622cad9cc1a3cbf044288abd0252192f`. They describe this checkout's
behavior, not proposed language features as though they already exist.

| TypeScript/Pi | Manuscript port | What I like / opportunity |
| --- | --- | --- |
| `async`, Promise, `Promise.all` | Ordinary functions and `TaskGroup` with `Task[ToolResult]` | I like having one function kind. Parallel work and its joined lifetime are explicit at the batch boundary. Typed task results require more collection/unwrap code. |
| Thrown tool/provider errors | `Result[T, Error]`, flat match and `try` | I like seeing the expected failure contract at each boundary. Programming faults remain separate. Adapters must consciously translate operational failures into Result. |
| Discriminated union objects | `Content`, `Role`, `Event`, `StopReason` alternatives | Exhaustive matching makes lifecycle handling reviewable. Optional fields on a shared Message record still permit invalid role/field combinations; distinct message variants could improve this application API. |
| TypeBox schema plus inferred parameters | `JsonValue` and a tool-specific validation function | The untrusted boundary is visible, and normalized arguments stay typed as JSON. A reusable JSON Schema validation library would remove repeated adapter work without adding syntax. |
| Structural interfaces and partial hook overrides | Nominal records, typed callbacks, complete ToolResult replacement | Explicit shapes improve local understanding. Complete replacement is clear but verbose; typed update records could express omission without `unknown` or object spreads. |
| Closure sharing in an event-loop application | Shared references with explicit `Synchronized` guards | The control queue and tool-event gate show exactly where sharing is protected. Read-only callback contracts still rely on discipline because exported record fields and nested payloads are mutable. |
| Array indexing returns an element (possibly undefined) | List indexing returns `Optional[T]` | Absence cannot disappear. Inside a proven in-range `entries()` loop, repeated `.unwrap()` is noisy; stronger tooling explanations or an indexed iteration API could help. |
| Positional arguments are unambiguous | A bare identifier matching a parameter name retains argument-name shorthand | Optional labels are pleasant, but `Config(model, sink)` bound the local `model` function to the String `model` field. `Config(stream: model, emit: sink)` fixes it. A targeted diagnostic explaining the binding would reduce correction cycles. |
| Async iterators deliver stream events | A provider callback delivers typed partial snapshots | Less runtime machinery is needed, and consumers settle before the next step. A standard typed stream/channel abstraction could supply buffering and backpressure for adapters that need decoupled consumption. |
| AbortSignal shared through callbacks | A synchronized cooperative control token | It is straightforward to trace cancellation. A source-usable cancellation handle that interrupts native HTTP/process waits would make this core easier to connect to real providers; this token alone cannot do that. |
| Fluent APIs and direct object methods | Exported functions operating on Agent records | Dependencies and operations remain clear. Source record methods require an explicit interface implementation, so functions avoid a ceremonial interface created only for method syntax. |

The compiler caught callback-label mismatches and missing Optional extraction
before native execution. The same source could then be checked, formatted,
compiled, and tested with one CLI. That is a strong fit for agent-authored ports.
The formatter's expansion of long grouped imports and higher-order calls also
made the source noticeably longer; compact layout around typed callbacks is an
opportunity to improve scanability while preserving the current syntax.

The most useful next improvements are libraries and tooling: JSON validation,
provider streaming adapters, cancellable native operations, and diagnostics for
mixed positional/name-shorthand calls. This port required no compiler, syntax,
standard-library, or runtime changes.
