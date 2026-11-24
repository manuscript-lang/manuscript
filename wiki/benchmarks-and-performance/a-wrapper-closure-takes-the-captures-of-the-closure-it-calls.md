[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A wrapper closure takes the captures of the closure it calls

Verified (2026-11-23): `promise(fn: work(i))` built two closure objects per start, the caller's and the standard library's `fn: complete(id, entry())` around it, and called the first through the second indirectly. `opt_inline_capture.c` fuses them: a `closure.new` that captures a known plain-data closure which its code only calls becomes a copy of that code holding the inner captures and calling the inner code directly. One allocation per start instead of two, and the work inlines into the wrapper (2,402 to 2,169 instructions for a start and wait).

The aliased set of known closures is needed (`ic_known_aliased`): after `promise` is inlined, the captured value is a copy of the caller's closure, not the `closure.new` itself. The fused copy keeps the wrapper's `scoped` flags; marking it `scoped` because the inner closure was fails verification ("kept by call.rt"), and plain captures need no flag.

Apply when: a library function wraps a caller's closure in its own (`fn: f(entry())`) on a hot path; do not restructure the library to avoid the wrapper.
Evidence: [pass](../../src/compiler/opt/opt_inline_capture.c), [numbers](../../bench/perf/async-primitives/README.md).
Verify: `tests/ownership-counts/promise_wrapper_closure.ms` (one allocation per promise).
