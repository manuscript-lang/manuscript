[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A close that inlines to nothing needs no cancellation shield

Verified (2026-11-16, `bench/perf/guards/cleanup`): a scope that owns a `Closeable` whose `close` is empty cost 152 instructions per scope under callgrind where a C loop with the same work costs a handful. 57 were `msrt_shield_exit` and 17 `msrt_shield_enter`, wrapped around a close the inliner had already deleted. The `simplify` pass now removes a `shield_enter` and the next `shield_exit` of a block when only plain operations and leaf runtime calls lie between them (nothing there can reach a cancellation point). `msrt_cleanup_discard` truncates instead of popping in a loop. 152 to 66 per scope; the remaining cost is `msrt_cleanup_push` (27) and `discard` (21), two calls that touch the per-task cleanup stack.

- The shield externs have roles (`ShieldEnter`, `ShieldExit`) set in both `rtcall.rs` and `elaborate.rs`; an extern declared in only one place keeps the role of whichever declaration came first.
- Next cut, not done: register the cleanup inline in generated code, or skip the registration for a stretch with no park and no faulting operation. Coordinate with the unwind pass owner (#4052) first.
- Callgrind: build programs with the reduced allocator reservation, see [callgrind-needs-a-smaller-allocator-reservation](callgrind-needs-a-smaller-allocator-reservation.md); a close or cleanup guard does not allocate, so its count is the same either way.

## Measured against C, same day (callgrind, instructions)

Hand-written C with `malloc`/`free`/`realloc` against the same program in Manuscript: 200 rounds of 1000 records with a string each, 64.5M C vs 34.9M; 200k `f"key-{i}-suffix"` temporaries 65.2M vs 53.6M; a 1M-element list grown by append 11.4M vs 11.4M; 300k small lists of records 122.7M vs 59.5M; a depth-14 tree built and freed 20 times 151.9M vs 124.0M; 20k promises 48.1M vs 43.2M; `Map[Int, Int]` with 200k inserts and lookups 33.9M vs 39.7M (1.17x). The one large gap is `s += "ab"` 200k times: 32.0M vs 2.4M, 111 instructions per `msrt_string_append` call against 12. Rewriting that function in place (no `memcpy`/`is_ascii` calls for short pieces) made it worse (168 per call): the cost is the tag decoding and the allocator size query, not the copy. The fix is an inline MIR fast path as `StringBuilder.append` has, which needs the block's spare capacity without an allocator call.
