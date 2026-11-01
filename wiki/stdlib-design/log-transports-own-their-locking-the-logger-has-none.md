# Log transports own their locking; the logger has none

Decision: `Logger` (a concrete type, not an interface, so `info[F: Data = Unit](message, fields: F? = none)`, `log` and `child` can be generic) never locks. `Transport` methods are plain `fn`; an implementation with mutable state guards it itself, as `StreamTransport` does with a `Shared[WriteStream]`. Child loggers copy a `Shared[Transport]` and read it with `get()`.

Why: an interface with a generic operation cannot be a value type, so a generic-field `Logger` cannot stay an interface. `WriteStream.write` is `var fn` and may suspend, so copies cannot share a stream without a lock somewhere; the lock belongs in the one type that owns the stream. `lock` itself does not spin: park blocks, the scheduler is cooperative so nothing runs between the check and the enqueue, and release wakes one waiter.

Verify: the "concurrent tasks never interleave a record" test in `tests/e2e/testdata/stdlib/log.ms` fails if `StreamTransport.write` stops locking.

The record encoder is Manuscript too: `log.ms` builds the line from `JsonValue` and `stringify`, and a transport's shut flag lives in its locked state. There is no native logger crate; `proposals/logger-encoder-in-manuscript.md` records the equivalence evidence. `Logger` is a value, so `set_level` is `var fn` and a copy keeps its own threshold.
