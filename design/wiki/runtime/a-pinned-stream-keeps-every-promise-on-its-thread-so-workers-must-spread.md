[Wiki](../index.md) › [Runtime and stdlib](index.md)

# A pinned stream keeps every promise on its thread, so workers must spread

Verified (2026-11-12, `bench/perf/web`, `MS_THREADS=2`): `serve` ran on one core. `start_on` runs a promise on the creating thread while a native stream is pinned there (`sched::pinned_here`), and the accept loop holds the serving handle, so every worker promise it made stayed on its thread; `/top` did not scale (22.8k req/s against 24.7k at one thread). `PromiseOptions(placement: Placement.Spread)` places a promise on the least loaded thread regardless of the pin and starts a thread when the limit allows; `serve` uses it for its workers.

Apply when: starting long-lived per-core workers from code that holds a native stream, or when a thread-scaling benchmark shows one busy thread in `top -H`.
