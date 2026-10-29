# A `Data` bound: values that can cross a byte boundary

## Summary

- Problem: "is this plain data?" was answered by three unrelated checks (`clonable`, `without_json_form`, `holds_resource`), none of which reached a generic `T`. A generic `show[T]` that calls `json.stringify` on a `FileHandle` checked clean and dropped the value at run time.
- Change: one computed bound `Data`, derived like `Clonable` (nothing to implement, no marker syntax). `T` is `Data` unless some part of it is a resource, behavior, or runtime handle. `json.parse`/`stringify` and the message types of workers and processes take `T: Data`; `without_json_form` and the message checks in `check_shared_use` are deleted.
- No negative marker: every exclusion already has a declaration site (`impl Closeable`, `extern type`, function and interface types).
- Companion changes: functions stop being `Clonable` (a list of lambdas still works); natives declare `Data` in `stdlib/*.ms` with `impl Data for X:`; `Queue`, `Deque` and `PriorityQueue` stop requiring `Clonable` for what they never copy.
- Cost: one function in `ms-check`, one parser rule (`interface Name: ...`, standard library only), `T: Data` on stdlib declarations. No runtime, MIR, or ABI change.

## Status

- Implemented in this change, 2026-10-29, against `1cb51434`. Stage 3b (moving the `receiver_requirements` table in `bindings.json` to bounded interfaces) landed afterwards; see Open questions.
- Direction (Chinmay, 2026-10-29): the resource distinction should cover "files and sockets and streams too, but may be in a negative fashion"; "it needs to be solid for the checker with clear enforceable rules that's easy to understand"; "map keys should be only hashable"; "no i don't want clonable functions, but list of lambda should be possible"; custom `JsonEncode` types are `Data` ("yes"); maps and sets are not `Data` ("Only list has a valid JSON representation"); "natives declare properties, let's get more things into manuscript so language is hardened"; "just do one pr".
- An independent skeptic review of the design (three rounds) shaped the rule: `Instant`, `Unit`, `Never`, recursion, the decoder's real key set, and the `JsonEncode` decode asymmetry (below) came from it.

## Problem

- Resources are `Closeable`: `closeable()` and class `Resource` (`ownership/classify.rs`). `FileHandle`, `Connection`, `Listener`, `Process` and the rest are `impl Closeable`; `ReadStream`/`WriteStream` are interfaces declaring `close()`.
- `without_json_form` ran only at three spawn sites, skipped type variables, and never asked about `Closeable`. `clonable` allowed functions against the `core.ms` doc. `json.parse[T]`/`stringify[T]` had no bound, and `ms-lower/src/json.rs` omitted a value with no JSON form silently.
- Non-goals: must-consume, effects, changing `Closeable`, transferring handles between processes, changing rendering (`"{x}"` stays total).

## Design

`Data(T)` holds when no part of `T` is a resource, behavior, or handle. First matching row decides; a recursive type is assumed `Data` only on the current path, and results are not cached across paths.

| # | `T` | `Data(T)` |
| --- | --- | --- |
| 1 | invalid type | true (error recovery) |
| 2 | type variable | true iff bounded by `Data` |
| 3 | primitive | true, except `Never`. `Unit` is `Data`: a `Unit` message is not encoded and a `Unit` field is omitted by design |
| 4 | function, interface value | false: behavior |
| 5 | `List[A]` | `Data(A)` |
| 5b | `Map`, `Set` | false: only `List` has a portable form (Chinmay, follow-up to #1905). A JSON object travels as `JsonValue`, which declares `impl Data` in the standard library |
| 6 | other native | true only with `impl Data for` it in the module that declares it (`Bytes`, `Decimal`, `BigInt`, `Duration`, `Timestamp`, `IpAddress`, `Cidr`); false for `Instant`, `Shared`, `Regex`, file, socket and process handles |
| 7 | record or alternative that is `Closeable` | false: resource |
| 8 | record or alternative with a `JsonEncode` impl | true: the codec owns the encoding; row 7 ran first |
| 9 | other record or alternative, including `Optional`, `Result`, `JsonValue` | every field and case payload, after substituting arguments, is `Data` |

- A record holding a `FileHandle` fails through row 6 on that field; there is no separate "holds resource" analysis.
- `data_blocker` returns the first failing part and a reason, and builds the message: `Report does not satisfy Data; field log is FileHandle, a resource (Closeable); send a path or an id and reopen it on the other side`.
- `Data` has no operations. `interface Data: ...` declares a property with no operations; only the standard library may (a user gets "an interface declares at least one operation"). An `impl` with no operations records its own evidence, because there is no method to carry it. `impl Data for X:` is allowed for an extern type in its declaring module, and for a record or alternative only in the standard library (`JsonValue`); user code gets an error.
- Not `Data`: `Instant` (monotonic, no JSON form), `Shared` (aliasing: the other side would get a silent copy).
- Known limit: the decoder reads a `JsonEncode` type structurally from its fields (there is no decode hook), so a codec-only type does not round-trip through `parse`. Row 8 keeps `JsonEncode` types accepted as before; a `JsonDecode` hook is the real fix and is out of scope.
- Known limit: `jencode_url` can still fail at run time for an unformattable `Url`, so encoding is total except for that case and `Unit`.

### Enforcement

`T: Data` is an ordinary bound, checked by the existing `bounds_satisfied`/`well_formed` path at every instantiation. It is written on `json.parse`, `json.stringify`, and on the message and result parameters of `Process`, `ProcessGroup`, `WorkerGroup`, `Worker`, `WorkerTransport`, `worker_channel`, plus `Envelope`, `processes.encode/decode`; wrappers (`fetch.json_body`, `Response.json`, `http.json`, `cli.command`, `log.record`) carry it. An unbounded `T` reaching any of these fails at its own definition ("T does not satisfy Data; it is a type parameter with no Data bound; add `T: Data`"), so the compiler is the audit. Tasks and channels move values in memory (`Shared` lanes) and are not bounded.

### Companion changes

- Functions are not `Clonable`. A function type does not record what a closure captured, so a copy could duplicate a resource. `List[fn() Int]` still builds, appends, iterates and calls; only `.clone()` on it is refused. `Queue` never cloned, so its bound is dropped; `PriorityQueue.peek` returns `ref Optional[T]` and drops `Clonable`; `Deque.pop_front`/`pop_back` move out with `List.replace`, and `to_list` (the one clone) moves to `interface DequeCopy[T: Clonable]`.
- `SortedMap`, `SortedSet` and `SortedEntry` still require `Clonable` (they clone keys and values), so a sorted collection of functions no longer compiles; nothing uses one.
- Natives declare `Data` next to their type: `impl Data for Bytes:`, and the same for `Decimal`, `BigInt`, `Duration`, `Timestamp`, `IpAddress`, `Cidr`. The Rust list of data natives is gone.
- Fixtures that tested the old lenient behavior changed by design in `tests/e2e/testdata/stdlib/json.ms`: function and `Instant` fields, interface values, every `Map` and `Set`, `parse[fn() Int]` and a record with a function field are now compile errors (reject fixtures `data-*.ms`). `strict` and the `stringify` doc now describe only `Unit` and `none`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/contracts.rs` | `data_blocker`, `Data` in `satisfies`/`implements`/`property_in`, `Kind::Function` not `Clonable`, marker-impl evidence, message | reject/accept e2e fixtures |
| `ms-check/calls.rs` | delete `without_json_form`, `mentions_shared`, message checks; keep the `Shared.take` guard | existing worker/process fixtures |
| `ms-check/checker.rs`, `stdlib.rs` | empty interface only in stdlib; marker impls skipped by the native binder | `reject/empty-interface.ms`, `reject/data-impl.ms` |
| `ms-syntax/parser.rs` | `interface Name: ...` | stdlib build |
| `stdlib/*.ms` | `interface Data`, bounds, `impl Data for`, queue and deque | e2e suite |
| `documentation/core-language/types/generics.md` | `Data` row | `make docs-check` |
| `ms-lower`, MIR, codegen, `ms-rt`, formatter | unchanged | existing |

## Alternatives

- Do nothing: only generic wrappers escaped the old concrete-type checks, so the bug was narrow; the bound closes it and replaces about 60 lines in `calls.rs` with one function.
- A declared negative marker or `T: !Closeable`: restates `impl Closeable` or needs new grammar and a solver; generic callers carry the bound either way.
- Reuse `Clonable` for JSON: admits `opaque` copies and `Instant`, rejects `IpAddress`; merging the two breaks `Instant` containers.
- Explicit `impl Data` on every record: boilerplate; `Clonable` set the precedent for computed.
- Drawbacks: public generics wrapping `log.record`, `cli.decode`, `Response.json` gain `T: Data`; a codec-only `JsonEncode` type is `Data` by the codec's word.

## Open questions

1. Stage 3b is done: `contains`, `index_of`, `last_index_of`, `distinct`, `to_set`, and `join` are bounded interfaces in `stdlib/collections.ms` (`ListSearch`, `ListDistinct`, `ListToSet`, `ListJoin`), and the `receiver_requirements` table and `native_receiver_available` are gone. `join` is one interface implemented for `List[String]` and for `List[Int]`, as `ListFloat32Sum` is for `List[Float32]`. `to_set` also requires `Clonable`, as `MapUpdate` does. `distinct` keeps its `Equal` bound and its hashed runtime path through `extern fn msrt_list_distinct[T]`, which lowering routes like the old native method, so it stays at native speed.
2. `Equal`/`Hashable`/`Clonable`/`Comparable` for natives declared in `.ms`: they have operations, so they need a bodyless declaration form first.
3. A `JsonDecode` hook so a custom `JsonEncode` round-trips; until then row 8 trusts the codec.
4. `opaque` types (#1853) are not `Data` once that lands: add the case to row 7 there.
