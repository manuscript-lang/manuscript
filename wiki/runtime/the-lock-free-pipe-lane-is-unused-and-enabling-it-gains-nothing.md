[Wiki](../index.md) › [Runtime](index.md)

# The lock-free pipe lane is unused and enabling it gains nothing

Verified (2026-11-18): the first lane in `crates/ms-rt/src/pipe.rs` (single-producer queue, "takes no lock at all") is reachable only from Rust tests. Every stdlib pipe closes the `Pipe`'s own writer and then calls `msrt_pipe_add_writer` from `writer()`, which sets `multi`, so all writes take the locked lane. Letting a first writer keep the lane (add a writer only flips `multi` while another end is open) gave no change: 4M `Int` across threads 670 vs 670 ms, request and reply 1100 vs 1100 ms. The cross-thread cost is about 150 ns per item of cache lines moving between cores, not the lock or the `SeqCst` fences (removing both changed nothing). Go does the same transfer in about 70 ns.

It also fails: `claim_reader` loads `waiting` and swaps it later, so a reader that has already taken the value through `Next::Again` and registered its next read can be claimed for a value that is gone, and `lane_pop` returns none ("a claimed reader finds the value just written" panics, 3 of 3 runs of a 4M-value producer and consumer). Do not enable the lane without fixing that claim; do not retry it for speed.

Also measured and not worth it: spinning 2 us before a cross-thread read or flush parks (request and reply 1100 to 620 ms, throughput unchanged), and scalar values inline in the queue item (no change). Real worker pools with 0.4 us of work per item run at Go's speed.

Apply when: changing pipe synchronization, or tempted to speed up cross-thread `Pipe` throughput.
Evidence: [`bench/perf/perf-bash-2026-11-18-concurrency.md`](../../bench/perf/perf-bash-2026-11-18-concurrency.md), [`pipe.rs`](../../crates/ms-rt/src/pipe.rs).
Verify: 4M `Int` through one writer and one reader on two threads (`MS_THREADS=2`) against `MS_THREADS=1`.
