[Wiki](../index.md) › [Runtime](index.md)

# Flow control lives in `@std/concurrency/flow.ms`

Decision (coordinator default, pending Chinmay's module answer): `retry`, `rate_limiter`, `CircuitBreaker`, `map_concurrent`, `Cache`, `Throttle`, `Debounce`, and `SingleFlight` are plain `.ms` over tasks, `Shared`, and the monotonic clock, with no Rust. Tasks run on one thread and switch only when they wait, so the limiter, breaker, and cache need no lock.

Constraints found while writing it:
- Function values cannot be cloned or captured by two closures: workers of `map_concurrent` share the callback as `Shared[fn(T) U]`.
- `Result` payloads are borrowed, so `CircuitBreaker.call` needs `T` and `E` `Clonable`.
- `Optional.get(default)` evaluates its default eagerly; do not pass `panic(...)`.
- The embedded stdlib is baked into `ms`; after adding a module run `cargo build --release -p ms-cli` before `ms test` sees it.

Apply when: adding resilience helpers, or moving them to another module.
Verify: `ms test tests/e2e/testdata/stdlib/flow.ms`.
`SingleFlight` waits by locking the leader's per-key `Shared` cell, so followers queue through `lock` and stay cancellable; `Shared.id()` is reserved for `lock`, so identity cannot be compared. Streams already compose with backpressure in `@std/io/streams.ms` (`map`, `take`, `concat`, `tee`, `copy`), so no Node-style `pipeline` was added.
