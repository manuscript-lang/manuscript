# Ancestor wait-cycle bookkeeping

This records issue 148's bounded allocation investigation. Ordinary ancestor
overlap must wait and return 7; same-operation reentry and potential ancestor
join cycles still fault. Admission edges exist before workers run, even when
there is no current lock waiter. Cancellation-aware restart tokens retain their
shared active flag; value removal tokens are owned and removed once.

The combined implementation keeps one counted destination inline, spills
distinct destinations into a map, returns noncancellable removal tokens by
value, and publishes/removes task and scheduler admission pairs in one graph
mutex hold. It retains the graph's eager semantics and component-to-graph lock
order. It does not shard the mutex or change the concurrency contract.

## Reproduce

Use the repository's pinned Go, writable caches, and otherwise idle hardware.
Prepare detached snapshots of the recorded baseline and unoptimized revisions.
Copy `pkg/runtime/work_wait_benchmark_test.go` from the candidate to both:
the baseline has no wait graph, so the portable benchmark file is separate from
`work_wait_contended_benchmark_test.go`. Copy that second file only to the
unoptimized snapshot. Do not copy runtime implementation files across variants.

From the candidate checkout:

```sh
GOCACHE=/tmp/wait-graph-go-cache GOPATH=/tmp/wait-graph-go-path \
python3 scripts/benchmarks/wait_graph.py \
  --go "$PWD/toolchain/go/bin/go" \
  --variant baseline=/tmp/wait-graph-baseline \
  --variant unoptimized=/tmp/wait-graph-unoptimized \
  --variant candidate="$PWD" \
  --output /tmp/wait-graph-results --runs 5 --benchtime 500ms --cores 1,4,16
```

The runner alternates variant order and records every sample, runtime source
hashes, pinned Go version, CPU affinity and Linux CPU quota. `--cores` names
GOMAXPROCS values; it does not assert that those physical cores are available.
The original 20 ms/100 ms contention case uses five iterations per sample and
checks the returned value. The ancestor-exclusion baseline cannot pass that
case, so it is compared only between the unoptimized and optimized permissive
implementations. Registered contention benchmarks use deterministic barriers.
The checked-arithmetic and SHA-256 tasks validate their results; they illustrate
different task sizes and are not a substitute for an application benchmark.

For a CPU profile use the same pinned Go with `GOMAXPROCS=1`, `-run '^$'`,
`-bench '^BenchmarkIssue148TaskGroup$'`, `-benchtime=10s`,
`-cpuprofile=/tmp/wait-graph.cpu` and `-o /tmp/wait-graph.test`.
Run profiles separately from timing samples. For parallel mutex contention,
profile `BenchmarkIssue148IndependentTaskThroughput` with `GOMAXPROCS=4` and
`-mutexprofile=/tmp/wait-graph.mutex -mutexprofilefraction=1`.

## Initial prototype samples

`prototypes.txt` and `baseline-and-batching.txt` retain the initial raw samples
on Linux amd64 / AMD EPYC 9V45 / pinned Go 1.25.1. The baseline was
`a80371dbf87cb6c9a2b8ffc051015708c3211cbe`; `reviewed` was
`37a60dcdd6b4bb5e93051575ace545f02aebbe35`. `inline`, `tokens` and `batched`
were isolated copies of that head with successively added bounded changes.
Samples used one-second runs and alternating order. The machine's CPU quota is
four CPUs, so GOMAXPROCS=16 measures oversubscription, not sixteen dedicated
cores. Host contention, GC and scheduling materially affect timings.

Profiling identified eight unconditional map/header/bucket allocations and four
removal closures per empty lifecycle. The combined prototype removes all twelve:
54 becomes 42 allocations, matching the baseline. Retained bytes fall from 3016
to 2216 B/op versus the baseline's 2104. Five paired single-processor medians were
3041 versus 3426 ns, a residual 385 ns / 12.7% cost. These are historical samples
before rebasing onto newer main; final samples and profiles are recorded below.


## Rebased candidate samples

`final-samples.txt` and `final-results.json` record five alternating 500 ms samples
per benchmark on the same machine and toolchain. The baseline is main
`a4970bc5`; the unoptimized graph is `110389de` (the reviewed correction rebased
onto that main); the combined candidate is `96fb93e8`. Runtime source hashes in
JSON pin the measured code independently of later evidence-only commits.

| Workload / GOMAXPROCS | Baseline median ns | Candidate median ns | Absolute change | Relative change |
| --- | ---: | ---: | ---: | ---: |
| Empty lifecycle / 1 | 3039 | 3323 | +284 ns | +9.3% |
| Eight-child group / 1 | 12931 | 14598 | +1667 ns | +12.9% |
| Independent empty tasks / 4 | 1872 | 1833 | -39 ns | -2.1% |
| Independent empty tasks / 16 | 2464 | 2652 | +188 ns | +7.6% |
| 1000 checked additions / 1 | 4561 | 4873 | +312 ns | +6.8% |
| 1000 checked additions / 4 | 2309 | 2342 | +33 ns | +1.4% |
| 1000 checked additions / 16 | 2918 | 3241 | +323 ns | +11.1% |
| SHA-256 of 64 KiB / 1 | 33920 | 33889 | -31 ns | -0.1% |
| SHA-256 of 64 KiB / 4 | 9176 | 9606 | +430 ns | +4.7% |
| SHA-256 of 64 KiB / 16 | 10734 | 10683 | -51 ns | -0.5% |

These are sample medians, not confidence intervals. Empty lifecycle ranges are
2980–3213 ns baseline and 3233–3390 ns candidate. Four-processor independent task
ranges are 1538–2100 versus 1707–2634 ns, and the oversubscribed sixteen-processor
ranges are 1878–2534 versus 2054–3055 ns. The SHA-256 single-processor ranges
33471–34401 and 33469–34264 ns overlap. No application-wide or zero-overhead
claim follows from these measurements. Empty callbacks use 42 allocations in
both baseline and candidate, versus 54 unoptimized. Candidate retained bytes
are 2216 versus 2104 B/op. The eight-child group spills into a map and retains
157 allocations versus 155 baseline and 195 unoptimized.

Registered contention compares the permissive variants: task lifecycle median
5848 → 5238 ns (-610 ns / -10.4%), 79 → 65 allocations and 4576 → 3584 B/op.
Lock-only median is 3068 → 2894 ns (-174 ns / -5.7%), with overlapping ranges
2960–3266 and 2848–3018 ns; allocations fall 26 → 24. The original timer scenario
is 100.515 → 100.505 ms, with overlapping ranges 100.445–100.568 and
100.443–100.609 ms. Timer resolution and scheduling hide submicrosecond costs.

`native-results.json` repeats the actual accepted `.ms` fixture through two
built CLIs after warming their caches, with the exact test filter and nine
alternating samples. Median wall time is 237.10 → 224.20 ms, but ranges overlap
224.98–272.53 and 211.14–319.11 ms. These include CLI startup, frontend/cache work
and the 100 ms program; they cannot isolate graph cost. Every run verifies
`1 tests, 0 failed`. `native-during-profiles.json` retains an earlier noisy
attempt made while profiling was active, excluded from the primary comparison.
Reproduce with `scripts/benchmarks/wait_graph_native.py --before <unoptimized-ms>
--after <candidate-ms> --source tests/e2e/testdata/accept/synchronized.ms
--output /tmp/wait-graph-native.json --runs 9`, with writable native caches.

## Residual overhead profiles

The separate ten-second CPU benchmark profiles include calibration and are not
paired timing samples. `baseline-cpu.txt`, `candidate-cpu.txt` and
`candidate-graph-cpu.txt` retain their summaries. Stacks through graph functions
account for 4.1% of sampled candidate CPU; graph mutex lock/unlock account for
about 2.0%, and cycle scanning (including empty map iteration) about 1.9%.
Profiling does not assign every nanosecond of the 284 ns residual: larger
embedded nodes/captures, stack scanning and scheduling also differ.

`parallel-cpu.txt`, `parallel-mutex.txt` and `parallel-graph-mutex.txt` profile
four-processor independent tasks. Graph call stacks account for 42.2% of sampled
mutex delay (1.32 of 3.13 seconds). This is aggregated waiter delay, not wall time
or CPU time, but it confirms that the global mutex remains a contention point.

The accepted safety contract requires admitted work and actual joins to remain
visible to future lock waits in a coherent order. Omitting eager edges when no
lock waiter exists breaks join-before-lock detection. The present implementation
pays bookkeeping and synchronization costs for that guarantee. The measured
284 ns is not proven to be an unavoidable lower bound: empty scanning could be
made cheaper, and another representation could alter constants. This bounded
change keeps the existing mutex architecture and leaves any wider redesign and
performance tradeoff to separate review. Cancellation pruning, shared token
idempotence, both insertion orders and bounded negative controls remain required.
