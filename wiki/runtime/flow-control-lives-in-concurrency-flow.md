[Wiki](../index.md) › [Runtime](index.md)

# Flow control lives in `@std/concurrency/flow.ms`

Decision (coordinator default, pending Chinmay's module answer): `retry`, `rate_limiter`, `CircuitBreaker`, `map_concurrent` and `Throttle` are plain `.ms` over promises and the monotonic clock, with no Rust. `Cache`, `Debounce` and `SingleFlight` were deleted with `Shared`.

Constraints found while writing it:
- `map_concurrent` runs its callback in stripes of promises that only read it.
- `Result` payloads are borrowed, so `CircuitBreaker.call` needs `T` and `E` `Clonable`.
- `Optional.get(default)` evaluates its default eagerly; do not pass `panic(...)`.
- The embedded stdlib is baked into `ms`; after adding a module run `cargo build --release -p ms-cli` before `ms test` sees it.

Apply when: adding resilience helpers, or moving them to another module.
Verify: `ms test tests/e2e/testdata/stdlib/flow.ms`.
Streams compose with backpressure in `@std/io/streams.ms`, so no Node-style `pipeline` was added.