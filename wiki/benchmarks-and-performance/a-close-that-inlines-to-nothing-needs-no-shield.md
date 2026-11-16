[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A close that inlines to nothing needs no cancellation shield

Verified (2026-11-16, `bench/perf/guards/cleanup`): a scope that owns a `Closeable` whose `close` is empty cost 152 instructions per scope under callgrind where a C loop with the same work costs a handful. 57 were `msrt_shield_exit` and 17 `msrt_shield_enter`, wrapped around a close the inliner had already deleted. The `simplify` pass now removes a `shield_enter` and the next `shield_exit` of a block when only plain operations and leaf runtime calls lie between them (nothing there can reach a cancellation point). `msrt_cleanup_discard` truncates instead of popping in a loop. 152 to 66 per scope; the remaining cost is `msrt_cleanup_push` (27) and `discard` (21), two calls that touch the per-task cleanup stack.

- The shield externs have roles (`ShieldEnter`, `ShieldExit`) set in both `rtcall.rs` and `elaborate.rs`; an extern declared in only one place keeps the role of whichever declaration came first.
- Next cut, not done: register the cleanup inline in generated code, or skip the registration for a stretch with no park and no faulting operation. Coordinate with the unwind pass owner (#4052) first.
- Callgrind: build programs with the reduced allocator reservation, see [callgrind-needs-a-smaller-allocator-reservation](callgrind-needs-a-smaller-allocator-reservation.md); a close or cleanup guard does not allocate, so its count is the same either way.
