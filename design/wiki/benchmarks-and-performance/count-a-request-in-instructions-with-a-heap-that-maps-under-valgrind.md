[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Count a request in instructions, with a heap that maps under valgrind

Verified: the runtime's allocator reserves 256 GiB of address space (`PAGES_SIZE`, `GROW_SIZE * GROW_CHUNKS` in `crates/ms-rt/src/alloc.rs`). Valgrind cannot map that, so under callgrind every allocation silently falls back to libc `malloc` and the profile charges allocation about 25% of a request that really costs under 10%. For a profile, shrink `PAGES_SIZE` to 8 GiB and `GROW_SIZE` to 16 MiB locally (never commit it), run with `MS_THREADS=1` so idle threads do not spin the reactor loop (that spin shows up as hundreds of millions of instructions), and divide the total by the requests the load generator counted. Wall clock and `utime` on this VM are too noisy to see a 5% change; instructions per request are stable to about 0.3%.

Numbers (2026-11-16, trivial handler on `bench/perf/http-tail`, keep-alive, one thread): bare C epoll server about 2.5k instructions per request; Manuscript 19.3k before, 15.9k after the content-type check and detached request tasks (see the dated section in the bench README). The request path is flat: no function above 3%, so the cost is layering (promise table, events, header tables, per-request strings), not one loop.

Apply when: profiling or optimizing a server path, or an allocation-heavy path, with callgrind.
Evidence: alloc.rs, [http-tail README](../../../bench/perf/http-tail/README.md).
Verify: callgrind total divided by request count is within 1% across two runs of the same binary.
