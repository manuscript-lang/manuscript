# Pipe pipeline across scheduler threads

Two producers write 500,000 values each into one `pipe[Int](64)`, one stage reads it and writes `v + 1` into a second pipe, and the main task reads the second pipe (1M values, 2M transfers). With the default thread count the promises can land on different scheduler threads, so every transfer crosses threads.

```sh
cargo xtask runtime && cargo build --release --locked -p ms-cli
target/release/ms build bench/perf/pipe-pipeline/main.ms -o /tmp/pipeline
for i in $(seq 20); do s=$(date +%s.%N); /tmp/pipeline >/dev/null; echo "$(date +%s.%N) - $s" | bc; done | sort -n   # wall seconds, sorted
```

Report the whole sorted list, not a median: the run is bimodal (all three promises stay on the main thread, or one or two are taken by another thread).

## 2026-11-08: Linux x86_64, 4 vCPUs, release

Wall seconds, sorted, same binary per row.

| build | runs |
| --- | --- |
| `eeecab6d` (main) | 0.137 0.493 0.500 0.510 0.540 0.548 0.875 0.929 0.972 0.982 0.999 1.005 |
| this change | 0.073 0.073 0.074 0.074 0.075 0.076 0.076 0.077 0.078 0.079 0.081 0.081 0.085 0.088 0.220 0.248 0.254 0.610 0.921 0.941 |

Cause: every item took the one table lock of all pipes three times (`msrt_pipe_write`, `msrt_pipe_buffered`, and the read side). With the producer and consumer on different threads that `std::sync::Mutex` was contended, and a contended hand-over is a futex wait and wake. Sampling a slow run showed threads in `lock_contended` and `futex`, not in the scheduler.

Changes: the table lock spins (the critical section is a few pointer moves) and yields after 256 spins; `msrt_pipe_write` answers `FULL` when the queue is above capacity, so `PipeSink.write` no longer asks `msrt_pipe_buffered`; `steal_wait_ns` reads the clock only when a start is queued, which an idle thread's spin polls.

Left: with the work on two threads a run is still 0.22 to 0.25 s, and with three threads 0.6 to 0.9 s, against 0.075 s on one. Go channels, same shape: 0.15 to 0.18 s.

## 2026-11-08 (#2926): lock-free first lane

The stage-to-main pipe has one writer and now takes no lock; the two-producer pipe keeps its lock. Wall seconds, sorted, all 40 runs per build, same session. [pipe-chain](../pipe-chain/README.md) is the all-lock-free shape.

| build | runs |
| --- | --- |
| `eeecab6d` (main) | 0.068 0.068 0.069 0.069 0.069 0.070 0.071 0.073 0.074 0.074 0.076 0.096 0.098 0.136 0.307 0.321 0.335 0.365 0.384 0.481 0.486 0.514 0.553 0.570 0.572 0.933 1.012 1.182 1.455 1.527 1.552 1.591 1.593 1.681 1.737 1.924 1.969 1.994 2.125 2.139 |
| this change | 0.064 0.065 0.067 0.067 0.074 0.165 0.170 0.173 0.198 0.201 0.202 0.209 0.215 0.216 0.237 0.256 0.265 0.277 0.297 0.309 0.328 0.328 0.355 0.416 0.495 0.596 0.706 0.866 0.872 0.906 0.922 0.946 0.951 1.005 1.021 1.034 1.043 1.043 1.049 1.101 |
