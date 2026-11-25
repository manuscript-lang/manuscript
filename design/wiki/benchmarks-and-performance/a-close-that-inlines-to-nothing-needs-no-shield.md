[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A close that inlines to nothing needs no cancellation shield

Note (2026-11-24): the cleanup stack (`msrt_cleanup_push`, `discard`) is deleted; only the shield measurement below still applies.

Verified (2026-11-16, `bench/perf/guards/cleanup`): a scope that owns a `Closeable` whose `close` is empty cost 152 instructions per scope under callgrind where a C loop with the same work costs a handful. 57 were `msrt_shield_exit` and 17 `msrt_shield_enter`, wrapped around a close the inliner had already deleted. The `simplify` pass now removes a `shield_enter` and the next `shield_exit` of a block when only plain operations and leaf runtime calls lie between them (nothing there can reach a cancellation point). `msrt_cleanup_discard` truncates instead of popping in a loop. 152 to 66 per scope; the remaining cost is `msrt_cleanup_push` (27) and `discard` (21), two calls that touch the per-task cleanup stack.

- The shield externs have roles (`ShieldEnter`, `ShieldExit`) set in the lowering and the unwind elaboration (Rust era); an extern declared in only one place keeps the role of whichever declaration came first.
- Compile cost (2026-11-18): the inline cleanup push is about 50k IR lines in a test binary of the yaml tests. It is now inline only in blocks on a CFG cycle (`blocks_in_loops`) and a plain `msrt_cleanup_push` call elsewhere: Release `ms test` CPU 13.4 s to 11.5 s, runtime of a 60M-iteration promise loop unchanged (1.95 s). Calling everywhere saved 10.3 s but slowed that loop 17%.
- Next cut, not done: register the cleanup inline in generated code, or skip the registration for a stretch with no park and no faulting operation. Coordinate with the unwind pass owner (#4052) first.

## Measured against C, same day (callgrind, instructions)

Compare against checked C: `Int` overflow checks (`__builtin_*_overflow`), bounds checks on every index, and overflow-checked capacity growth, `-O2 -fno-builtin-malloc -fno-builtin-free -fno-builtin-realloc` (Chinmay, 2026-11-16). Unchecked C understates the baseline by up to 35% on index-heavy loops (a 1M `List[Int]` append and sum: 11.4M unchecked, 15.4M checked).

| Program (callgrind, instructions) | Checked C | Manuscript |
| --- | --- | --- |
| 200 rounds of 1000 records with a string each | 65.3M | 34.9M |
| 200k `f"key-{i}-suffix"` temporaries | 65.4M | 53.6M |
| 1M-element list grown by append, then summed | 15.4M | 11.4M |
| 300k small lists of records | 121.1M | 59.5M |
| `Map[Int, Int]`, 200k inserts and lookups | 34.7M | 39.7M (1.14x) |
| depth-14 tree built and freed 20 times | 150.2M | 124.0M |
| 200k parse calls, one in four fails | 30.5M | not remeasured |
| 100k clones of a record with a string and two tags | 59.2M | not remeasured |
| 1M scope-end closes (`Res.close`) | 5.25M | see the guard |
| `s += "ab"` 200k times | 2.39M | 32.0M before spare room, 5.0M after |

The earlier unchecked numbers were slightly lower for C (listint 11.4M, mapint 33.9M, sb 2.39M); none of the verdicts changed except that the `Map` gap narrowed from 1.17x to 1.14x. The `s += "ab"` gap was 111 instructions per `msrt_string_append` call against 12; rewriting that function in place did not help (the cost is tag decoding and the allocator size query), so the fix is the inline MIR fast path over spare room ([spare room](strings-record-their-spare-room-in-the-length-word.md)).
