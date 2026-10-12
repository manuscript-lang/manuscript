+++
title = "Standard imports and API typing"
weight = 34
+++

# Standard imports and API typing

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Most standard names must be imported explicitly. Six intrinsic types and the two equality interfaces are available automatically. Native implementation or special compiler support does not make a name globally visible.

This page is the exact reference for standard exports, their identities, and API typing. A trusted manifest may implement these declarations but cannot change their source identities or typing rules.

## Names and identity

Every module implicitly sees only `Bool`, `Int`, `Float`, `String`, `Unit`, `Never`, `Equal`, and `Hashable`, as specified by [module declarations](../../modules-and-capabilities/modules/declarations.md). The two interfaces describe equality and hashing; passing values requires no sharing bound. Ordinary behavior requirements use imported operation contracts.

`@std` is a reserved directory supplied by the pinned compiler/runtime distribution. Each path below is a standard module, and each name is an individual export. There are no wildcard imports or automatic imports of other exports from the same module.

| Module | Exports |
| --- | --- |
| `@std/decimal.ms` | `Decimal` |
| `@std/bytes.ms` | `Bytes` |
| `@std/collections.ms` | `List`, `Map`, `Set`, `MapEntry` |
| `@std/optional.ms` | `Optional` |
| `@std/result.ms` | `Result` |
| `@std/cleanup.ms` | `Closeable` |
| `@std/tasks.ms` | `parallel`, `check_cancelled`, `ExecutionError`, `OperationId`, `Scheduler`, `SchedulerFailure`, `WorkStatus`, `StartError` |
| `@std/faults.ms` | `panic` |
| `@std/time.ms` | `Duration`, `Instant`, `Clock`, `clock`, `wall_clock` |
| `@std/io.ms` | `Files`, `File`, `ReadStream`, `WriteStream`, `IoError`, `stdin`, `stdout`, `stderr`, `files` |
| `@std/cli.ms` | `arguments`, `environment` |

```manuscript
import Result from "@std/result.ms"
import ExecutionError from "@std/tasks.ms"
import parallel from "@std/tasks.ms"
```

Imports establish stable nominal identities independent of the application. Imported names follow ordinary collision and shadowing rules; unimported standard names are not reserved. A local declaration with the same spelling never acquires standard operators, cleanup recognition, callback checks, or native members.

The [general-purpose package guide](../packages/_index.md) documents additional module exports and [common errors](../packages/contracts.md). Imported accessors provide FileSystem, Entropy, WallClock, System, and Network services. Network includes TCP/UDP/TLS/client/DNS operations. These additions retain explicit imports and nominal identities.

## Syntax and compiler support

Some library identities need compiler support while remaining explicit exports:

- Ordinary bracket literals require the canonical `List` import in the module. The `tasks` literal of the imported `parallel` binding is a positional pack and does not require `List`.
- A `d`-suffixed literal requires the canonical `Decimal` import. Decimal arithmetic and interpolation keep their specified behavior.
- `Optional` and `Result` are standard alternatives with ordinary case lookup. Optional also provides [presence checks and extraction methods](../../core-language/types/optionals.md#checking-and-extracting-values). `try` recognizes the canonical Result identity; a user-defined alternative named Result does not qualify.
- `for`, collection derivation, and guarded layout recognize the standard collection identities. `MapEntry` is an exported record; map iteration can infer it without importing its name.
- `with` recognizes the canonical Closeable implementation, or an operation contract declaring the exact close signature. A module writing `impl Closeable` or a Closeable bound imports that name; using an already-typed resource does not require an otherwise unused import.
- Runtime API special checks attach to the resolved standard callee. A user-defined `parallel` is an ordinary function and never receives pack rules.

A missing or substituted List/Decimal import rejects the corresponding literal during resolution/type checking. Inferred library values may be matched, traversed, or used through their declared members without importing every type in their public signatures. Naming such a type or using its unqualified expression constructors requires its own import. Primitive receiver members in the [data API](../data-and-io/operations.md) are fixed standard bindings and can likewise produce inferred library values; they add no ambient type names. Importing a type supplies its declaration; imported host accessor functions return services from the current execution.

`OperationId` is the single opaque identity for runtime operations, whether started by a joined group or admitted by a Scheduler service. It has no source constructor and no implicit equality or hashing, and it grants no scheduling, joining, or transfer authority. A Scheduler service's `status` and `cancel` act only on IDs it admitted. `WorkStatus` has nullary cases `Running`, `Succeeded`, `Failed`, `Cancelled`, `Crashed`, and `Unknown`; qualify these case names when necessary. `StartError` has `Closed` and `Full`. `IoError` has `Closed`, `InvalidInput`, `Unavailable`, and `Failed(message: String)`. These are ordinary alternatives. Execution errors are defined in [joining](../../concurrency/joining.md).

```manuscript
fn panic(message: String) -> Never
fn check_cancelled() -> Unit
```

These lines specify bindings rather than complete source modules. `check_cancelled` unwinds the current execution if it has stopped; it returns `Unit` otherwise.

## Joined concurrency

All concurrency names are explicit library exports. The call below requires the `parallel` import from `@std/tasks.ms`; no concurrency operation, error type, work identity, or service expands the intrinsic type/bound list. Every concurrency name, including `check_cancelled` and `OperationId`, is exported by `@std/tasks.ms`. Timeouts and scheduling are implemented by library/runtime bindings.

`parallel` requires `tasks` and permits only the optional named argument `timeout: Optional[Duration]`. Omission means no added limit; an inherited deadline still applies. Negative timeouts fault. Zero-timeout, stop, join, and outcome rules follow [joining outcomes](../../concurrency/joining.md#group-lifecycle).

`tasks` must be a bracket literal, optionally grouped in parentheses. Each position must independently resolve to a zero-parameter function `fn() -> Ri`. The binding produces `Result[Pack[R1, …, Rn], ExecutionError]`. Here `Pack` is compiler notation, with no source type-name spelling or source constructor. Existing lists are rejected.

Standard concurrency callbacks are ordinary function values. Parameters, fields, collections, and generic forwarding preserve their call behavior. Operations may return functions or services; resource lifetime remains governed by explicit cleanup.

### Function values

`parallel` requires a direct call because its literal pack determines a heterogeneous result shape. The `Scheduler` constructor also remains a direct constructor call.

`scheduler.start` and HTTP admission methods may be saved or passed to helpers. Source contracts can expose ordinary callback-taking operations, including wrappers around scheduled submission.

### Inferred result packs

A pack can be inferred into a local, carried through an inferred generic type argument, bound in a Result match, returned through a generic `T`, and destructured with exact positional arity. It cannot be written in an annotation, explicit type argument, field, or named function signature. Nested inferred packs retain their exact shape. Pack identity is the ordered sequence of position types; the empty pack is distinct from `Unit` and `List`. Packs may be passed between operations, but have no equality, hashing, iteration, field access, or indexing. An ordinary generic identity function can preserve a parallel pack without a new source syntax.

## Scheduler service

`Scheduler()` constructs a synchronized work service under the current execution. Optional `limit: Optional[Int]` and `history_limit: Optional[Int]` impose no caps when omitted. A supplied admission limit must be positive; history may be zero. `reporter: Optional[fn(failure: SchedulerFailure) -> Unit]` defaults to host diagnostics, and optional `drain: Optional[Duration]` defaults to zero. Retained reporter resources must remain usable through shutdown. See [scheduling work](../tasks/scheduler.md).

```manuscript
type SchedulerFailure:
    case Failed(operation: OperationId, cause: String)
    case Crashed(operation: OperationId, message: String)

# Operations of the native Scheduler service:
fn after(duration: Duration, operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]
fn every(interval: Duration, operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]
fn restart(id: OperationId) -> Result[OperationId, StartError]
fn start(operation: fn() -> Result[Unit, String]) -> Result[OperationId, StartError]
fn cancel(id: OperationId) -> Unit
fn status(id: OperationId) -> WorkStatus
fn close() -> Unit
```

`start` accepts an ordinary callable. This is one operation signature: Operations without domain errors explicitly return `ok(value: unit)`, and operations with domain error types explicitly translate them to String using `match`. There is no generic method, implicit formatting of arbitrary errors, or overload. `Scheduler` explicitly implements `Closeable` in the standard binding.

### Failure reporting

The reporter receives `Failed` for a returned String error and `Crashed` for a programming fault. Cancellation changes status rather than producing a domain error. Reporter calls are serialized, may suspend, and run outside transition locks under a shielded service context. Shutdown waits for them.

When a limit is supplied, at most `limit` completion reports may be pending. With no limit, reports queue without an imposed cap. Capacity exhaustion or a reporter fault sends both the original diagnostic and the reporting failure/overflow diagnostic to the host sink. A reporter fault never invokes the reporter recursively. The sink itself has a bounded buffer; overflow increments a retained counter and emits a host stderr diagnostic. Uncooperative reporters remain subject to host escalation.

Status eviction never reuses an ID for different work. An ID the service did not admit, including one from another service or a joined group, returns `Unknown` from `status` and is a no-op for cancellation.

## Capabilities and data operations

The host's authority roots and stream signatures are defined by [Command-line programs](../packages/cli.md) and [streams](../data-and-io/streams.md). Standard collection, byte, text, numeric, and duration members are defined in [minimum data operations](../data-and-io/operations.md). Source code cannot add implementations or members to intrinsic or standard-library types. Source types may implement standard contracts in their defining module or through [local extensions](../../core-language/types/contracts.md#coherence-and-visibility).

General user type packs and user-defined generic interface operations are unsupported. Ordinary function defaults permit optional source parameters. HTTP server registration follows the [request API](../packages/http.md#request-api).

## Data services and additional host capabilities

`@std/queues.ms` exports `Queue`; `@std/sync.ms` exports `Synchronized` and `SynchronizedGuard`; the data modules export their respective builders. Their exact contracts live in [queues](../data-and-io/queues.md), [synchronized values](../data-and-io/synchronized-state.md), and [builders](../data-and-io/builders.md). None is ambient. Opaque constructor parameter names are not source fields.

`@std/time.ms` also exports `sleep(duration: Duration) -> Unit`, a sequential cancellable delay. Negative duration faults; zero performs a cancellation checkpoint.

`@std/http.ms` exports the HTTP request and server types in [HTTP](../packages/http.md). `Network.serve` accepts an ordinary handler and may be stored as a bound method. `@std/process.ms` exports `Commands`, `CommandOutput`, and `CommandError` in [streams](../data-and-io/streams.md). Import `network()` from `@std/net.ms` and `commands()` from `@std/process.ms` to obtain those host services.
