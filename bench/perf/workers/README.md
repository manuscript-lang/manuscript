# Worker scaling

Eight CPU-bound jobs (`fib(38)`) sent round-robin over 1, 2 and 4 workers of a `WorkerGroup`; each worker computes its jobs and sends the results back over its channel. The checksum must match across worker counts. Reproduce with `MS=./target/release/ms sh bench/perf/workers/run.sh 3` (best of N wall times, milliseconds); compare only runs from one machine.

## main at c1b81215 (2026-10-25)

linux/amd64, four cores, Release build (LLVM).

| workers | best ms | speedup |
|---:|---:|---:|
| 1 | 1922 | 1.00x |
| 2 | 989 | 1.94x |
| 4 | 486 | 3.95x |

Workers are OS threads with their own isolate, so CPU-bound work scales with cores. Messages cross as JSON, so send work in chunks that take longer than the message does to move.
