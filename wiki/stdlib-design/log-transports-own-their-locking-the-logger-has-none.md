[Wiki](../index.md) › [Stdlib design](index.md)

# Each logger owns its transport; there is no lock

Decision: `Logger` (a concrete type, so `info[F: Data = Unit](message, fields: F? = none)`, `log` and `child` can be generic) never locks. `Transport` has `duplicate()`: `child` gives the child its own transport onto the same destination (a file transport opens its own handle), so loggers on several threads share nothing and a transport needs no locking. Records are single appends, so the OS keeps them whole.

Why: promises only read their captures and there is no `Shared`, so one transport cannot be mutated from several threads. Closing a logger closes only its own transport. Logger scope end no longer runs a custom transport's `close` (it did through `Shared[OwnedTransport]`); making `Logger` `Closeable` would consume it on `close()` and is an owner decision.

Verify: "loggers on several threads never interleave a record" in `tests/e2e/testdata/stdlib/log.ms`.

The record encoder is Manuscript too: `log.ms` builds the line from `JsonValue` and `stringify`. `Logger` is a value, so `set_level` is `var fn` and a copy keeps its own threshold. Call fields go under `data` and `child` fields under `context`, both as `stringify` text written as is.
