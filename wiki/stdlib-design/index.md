[Wiki](../index.md) › Standard-library design

# Standard-library design

Stdlib API shape, failure modes, naming, construction.

- [Buffering, pipes and virtual file trees reuse existing primitives](buffering-pipes-and-virtual-file-trees-reuse-existing-primitives.md): `buffered.ms`, channel-backed pipes, `section`, and the `FileTree` interface with `MemoryTree` and `walk`; `embed` awaits a language decision.
- [Calls that fail only on a programmer's constant return plain values; fixed-width codecs are methods](calls-that-fail-only-on-a-programmer-s-constant-return-plain.md): `String.pad_start/pad_end` and `Float.to_fixed/to_precision/to_exponential` return `String`.
- [Collections: construct from a list, keep insertion order](collections-construct-from-a-list-keep-insertion-order.md): `Set(list)` constructs from a list; Map and Set iterate in insertion order; mutators are verbs that return the receiver.
- [Every public module needs a fixture, a guide comment, and a doc comment with an example](every-public-module-needs-a-fixture-a-guide-comment-and-a-do.md): public modules have a fixture in `tests/e2e/testdata/stdlib/*.ms`, and all stdlib prose lives in `stdlib/*.ms` (book Markdown is generated b…
- [Fallible APIs return domain error values](fallible-apis-return-domain-error-values.md): prefer named domain failures; Result and value-only helpers need no Error implementation, while reporting boundaries remain opt-in.
- [Host operations are module functions, not getter handles](host-operations-are-module-functions-not-getter-handles.md): ambient host operations are module functions (`read_file(path)`); types only for configured or stateful values.
- [List operations that need an element bound are written in Manuscript](list-operations-that-need-an-element-bound-are-written-in-ma.md): `sum`, `min`, `max` and the comparator-less `sorted()`/`sort()` live in the source half of [collections.ms](../../stdlib/collections/collections.ms), a…
- [List structure ops: `entries()` already is `indexed`; piece lists come from one runtime call](list-structure-ops-entries-already-is-indexed-piece-lists-co.md): `List.entries()` (`ListEntry` with `index`, `value`) covers the "walk with an index" need, so no `indexed()` alias was added.
- [Log transports own their locking; the logger has none](log-transports-own-their-locking-the-logger-has-none.md): `Logger` is a concrete type with generic optional-fields level methods and never locks; `StreamTransport` guards its stream.
- [One spelling per operation; consolidate by domain](one-spelling-per-operation-consolidate-by-domain.md): the stdlib reorganization (#659) removed duplicate routes: `cli` moved into `process` (`process.arguments`, `process.control().environment()…
- [Options records as plain defaults; fetch helpers are methods](options-records-as-plain-defaults-fetch-helpers-are-methods.md): a function that takes a settings record declares it `options: FetchOptions = FetchOptions()`, never `FetchOptions? = none`, so callers write…
- [Pick the failure mode by cause, then the shape](pick-the-failure-mode-by-cause-then-the-shape.md): absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults.
- [Text in, bytes by explicit sibling](text-in-bytes-by-explicit-sibling.md): write-like operations accept `String`; the raw form is a `_bytes` sibling (`write_bytes`, `send_bytes`, `request_bytes`).
