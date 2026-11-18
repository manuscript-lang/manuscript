# Perf bash, 2026-11-18: concurrency and I/O throughput

Base `main` at e36d2729, Release `ms` from `make build`, 4 vCPU shared Linux VM. Go 1.x `go build`, Rust `rustc -O`. Programs are scratch workloads (not committed); ms (milliseconds), medians of 3 or more alternating runs. Each ms program has the same shape as its Go port (same chunking, same sizes).

## Where Manuscript stands

| Workload | Manuscript | Go | Rust |
| --- | ---: | ---: | ---: |
| 500k promises, create and wait one at a time / in batches of 1000 | 104 to 164 / 121 to 155 | goroutine and channel 287 / 268 | none |
| 500k timers (sleep 10 to 30 ms) all pending at once | 280 | 514 | none |
| CPU fan-out, 4M primes in 16 chunks, 1 / 2 / 4 threads | 1051 / 555 / 304 | 437 (4 procs), 1720 (1 proc) | none |
| 2,000 `echo` children, 8 at a time | 764 to 918 | 753 to 837 | 763 to 775 |
| 20,000 small files written and read, 16 / 128 at a time | write 1.4 to 2.3 s, read 75 / 79 | write 1.4 to 1.5 s, read 98 to 122 / 79 to 107 | disk bound |
| 136 MB `cat` through stdin and stdout | 293 | 285 | none |
| 3M lines uppercased through `lines` | 363 | 941 to 974 | none |
| Directory walk, 21,200 entries | 12 to 14 | 16 to 19 | none |
| Echo over loopback TCP, 200 MB in 64 KiB chunks | 76 | 52 | none |
| Worker pool, 500k jobs over pipes, about 0.4 us of work each | 236 to 249 | 222 to 226 | none |
| Worker pool, 500k jobs, about 3 us of work each | 789 to 832 | 822 to 829 | none |

Nothing here is a gap worth a fix. Spawn, timers, thread scaling, files, process spawn and line filters are at or ahead of Go; the kernel dominates the rest.

## Gaps measured and left alone

| Workload | Manuscript | Go | Why it stays |
| --- | ---: | ---: | --- |
| Pipe, one writer to one reader on another thread, 4M `Int`, capacity 1024 | 650 | 280 (chan; 140 per 2M measured), Rust `sync_channel` 70 to 90 | Trivial work per item. One thread runs it in 150 ms. |
| Request and reply over two pipes, 500k rounds, two threads | 1100 | 212 (85 per 200k measured) | Same. One thread: 280. |
| Echo over loopback TCP, 31k rounds of 64 bytes | 305 to 330 | 215 (`splice`, so not like for like) | 10 system calls per hop, mostly kernel. |
| 20,000 short connections, 4 to 128 at a time | 810 to 960 | 420 to 540 | A listener pins its thread, so accept and the handlers share one core; Go spreads over four. `serve` spreads HTTP; `Listener.accept_pending` spreads raw TCP (section below). |

The worker-pool rows above show the pipe cost disappearing once an item does real work: 500k jobs at 0.4 us each take 236 ms against Go's 222 ms, and at 3 us each the two are equal.

### Tried and dropped (each measured, none kept)

| Change | Result |
| --- | --- |
| Keep the descriptor registered with the poller between waits for plain sockets (`WAIT_KEEP`, drops one `epoll_ctl` per wait) | 62,500 fewer system calls per 31k rounds, wall 5% lower (sys 0.33 to 0.29 s); not worth the ET soundness argument. |
| Spin 2 us for a peer on another thread before a pipe read or flush parks | Request and reply 1100 to 620 ms; throughput unchanged at 650; costs 2 us of the thread per park when nothing arrives. Not kept: a stress-probe gain with a tax on every slow pipe. |
| Store scalar pipe values in the queue item instead of one heap block each | Throughput 650 to 650 while the lock was contended; kept once the lock fix below removed that bottleneck. |
| Use the lock-free first lane for the single writer | Throughput 670 to 670, request and reply unchanged. The lane was never used by `pipe()` and turning it on tripped a race, so it is deleted (#4507); see the wiki page. |
| Remove both `SeqCst` fences from the single-writer path (experiment only) | No gain (734 to 874); the cost is cache lines moving between cores (about 160 ns per item), not locks or fences. |

## Change: pipes hold their lock for a swap, and the reader polls without it

Callgrind cannot see this; gdb stack samples of a two-thread producer and consumer put a quarter of the samples in `sched_yield` from `msrt_pipe_write`: the writer spun on the pipe lock while the reader held it to copy up to 256 queued items into its own queue, then retried it three times per empty poll. Four changes, all in `ms-rt/src/pipe.rs`:

- the reader takes the whole shared queue by swapping the two buffers (a few pointer moves under the lock) instead of draining up to 256 items;
- an empty poll (`msrt_pipe_try`) reads the queue length and returns without the lock;
- the queue length sits on a cache line of its own, apart from the flags the reader reads for every value;
- values of one word or less that own nothing (`Int`, `Float`, `Bool`, plain records) are stored in the queue slot, not in a heap block freed by another thread.

The first lane that `pipe()` never used is deleted (#4507).

| 4M `Int`, capacity 1024, one writer and one reader | before | after |
| --- | ---: | ---: |
| two or more threads, 15 interleaved runs: min / p25 / median / p75 ms | 636 / 644 / 698 / 734 | 388 / 468 / 546 / 592 |
| `MS_THREADS=1` ms | 159 | 127 |
| request and reply, 500k rounds, one thread ms | 328 | 320 |
| request and reply, 500k rounds, two threads ms | 1178 | 1177 |
| worker pool, 500k jobs of about 20 ns, ms | 281 to 319 | 257 to 277 |

Go on the same machine: 310 ms for the same throughput case with 4 procs (200 with 1), and request and reply 170 to 190 per 400k rounds at any proc count, because Go keeps the two goroutines on one thread. Run-to-run spread on this VM is large (single runs 230 to 830 ms), so the table uses medians of interleaved runs.

Tried and dropped on top: spinning for a writer on another thread before the read parks (request and reply 1119 to 694, throughput 614 to 796: the spin reads the line the writer writes on every value).

### Change: `Listener.accept_pending` spreads raw TCP connections

A `Connection` belongs to the thread that uses it, and so does the listener that made it, so a program that accepts and serves on one listener ran its handlers on the accepting core. `serve` avoids this for HTTP by accepting a raw socket handle and adopting it on a worker thread. `Listener.accept_pending` exposes the same two steps: it returns a `PendingConnection` (a socket not yet bound to a thread), and `PendingConnection.adopt` on the thread that should serve it gives the `Connection`. A handler promise started with `Placement.Spread` does the adopt, so each connection lands on the least loaded thread. No new scheduling code: it is `Placement.Spread` plus the handoff `serve` already uses.

20,000 short connections, 128 at a time, echo of 11 bytes, median of 9 runs (4 vCPU VM, clients in the same process and spread):

| server | ms |
| --- | ---: |
| `accept` plus handler on the listener's thread | 843 |
| `accept_pending` plus handler `Placement.Spread` | 766 |
| Go | 493 |

The handlers here do almost no work, so the saving is small: the cost per connection is mostly kernel time (sys 0.9 s of 1.6 s CPU, Go the same) and the accept loop. With 300,000 loop iterations of work per connection (1,024 connections): 1758 ms pinned, 1229 ms spread. The remaining gap to Go on empty handlers is user-space cost per connection (about 0.7 s against 0.4 s), not placement.
