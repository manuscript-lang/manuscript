# Pipe chain across scheduler threads

One producer writes 1M values into a `pipe[Int](64)`, one stage reads it and writes `v + 1` into a second pipe, and the main task reads the second pipe. Every pipe has a single writer, so the lock-free lane carries it. Build and time it as in [pipe-pipeline](../pipe-pipeline/README.md), and report the whole sorted list: a run is fast when the promises share a thread and slow when they spread.

## 2026-11-08: Linux x86_64, 4 vCPUs, release

Wall seconds, sorted, 40 runs per build.

| build | fast runs | slow runs |
| --- | --- | --- |
| `eeecab6d` (main) | 33 at 0.064 to 0.090 | 0.782 0.811 0.813 0.896 0.986 1.068 1.122 |
| this change (#2926) | 39 at 0.066 to 0.082 | 0.568 |

Cause of the slow runs: the one lock per pipe handed between two spinning threads (user time was twice real time, sys near 0). A pipe with one writer and one reader needs no lock: the writer appends to a segmented queue and publishes a count, the reader consumes and publishes its own, and each side re-reads the other's count only when its cached copy says the queue is empty or over capacity. Pipes that call `add_writer` keep the locked queue.
