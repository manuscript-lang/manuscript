[Wiki](../index.md) › [Runtime](index.md)

# Concurrency is promises and pipes only

Decision: task groups, worker threads, process groups, channels, `Shared`, `lock` and `once` were deleted. Work starts with a call that returns a `Promise[T]` or with `promise(fn: ...)`; a promise only reads its captures (rule 5), and changes reach their owner over a `pipe`. Do not re-add a shared mutable cell, a lock or a cache to work around that; give the state one owner.

Streams follow the same model ([stream redesign](../../proposals/stream-redesign.md)): `ReadStream[T]` and `WriteStream[T]` are opaque and generic; `write` never waits and `flush()` is the backpressure point; a stream loop says `for x in s.wait()` and a bare `for` over a stream is a checker error; `Source`/`Sink`/`Transform` implement new ones; `serve` runs on every core and handlers only read shared values. The public rules live in the [concurrency guide](../../documentation/core-language/concurrency/_index.md) and `ms skill`; change them together.

Consequences found while migrating: a promise reading a resource keeps it borrowed until the promise is dropped or moved into `wait_all`, so close the resource after that; a `var fn` method cannot run inside a promise, so a handle whose `next` or `read` is `var` cannot be waited on from one while another closes it; a logger on each thread owns its transport (`Transport.duplicate`), so a custom transport's `close` is not run at logger scope end; `Debounce`, `Cache` and `SingleFlight` were dropped with their locks.

Apply when: porting code or tests that shared state between concurrent work.
Evidence: [promise.ms](../../stdlib/concurrency/promise.ms), [promise-semantics.ms](../../tests/e2e/testdata/stdlib/promise-semantics.ms), [concurrency guide](../../documentation/core-language/concurrency/_index.md).
Verify: `ms test tests/e2e/testdata/accept/implicit-close-shielded.ms`.
