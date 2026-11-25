[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Count a request in instructions, with a heap that maps under valgrind

Verified: count a request in instructions, not wall clock, which is too noisy on this VM to see a 5% change: instructions per request are stable to about 0.3%. Run `valgrind --tool=callgrind` with `MS_THREADS=1` so idle threads do not spin the reactor loop (that spin shows up as hundreds of millions of instructions), and divide the total by the requests the load generator counted.

Numbers (2026-11-16, trivial handler on `bench/perf/http-tail`, keep-alive, one thread): bare C epoll server about 2.5k instructions per request; Manuscript 19.3k before, 15.9k after the content-type check and detached request tasks (see the dated section in the bench README). The request path is flat: no function above 3%, so the cost is layering (promise table, events, header tables, per-request strings), not one loop.

Apply when: profiling or optimizing a server path, or an allocation-heavy path, with callgrind.
Evidence: [http-tail README](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/http-tail/README.md).
Verify: callgrind total divided by request count is within 1% across two runs of the same binary.
