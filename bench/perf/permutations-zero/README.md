# Zero-size permutations

Build `main.ms` in Release, then pass input length, chosen size, repetition
count and expected output count. Setup is excluded. Every call checks the
output count and first permutation's length and contributes to a printed
checksum. The e2e fixture separately verifies order and independent copies.

```sh
MS_BACKEND=cranelift ms build bench/perf/permutations-zero/main.ms --build-type Release -o /tmp/permutations
taskset -c 0 /tmp/permutations 1000000 0 20 1
taskset -c 0 /tmp/permutations 100000 0 100 1
taskset -c 0 /tmp/permutations 5 0 1000000 1
taskset -c 0 /tmp/permutations 0 0 1000000 1
taskset -c 0 /tmp/permutations 1 1 1000000 1
taskset -c 0 /tmp/permutations 5 1 500000 5
taskset -c 0 /tmp/permutations 5 2 200000 20
taskset -c 0 /tmp/permutations 5 5 20000 120
```

Compare alternating baseline/candidate processes on the same machine, using
the same compiler and runtime. Do not time builds or other tests concurrently.

## 2026-11-09: skip the unused position bitmap (#3276)

Main source `6c082973c44720ed3c22f235b233642d37aae622`, compiler/runtime
`5b2a2644da2a97c6db9788bf5a1c0d756c9d05f6`, Linux x86-64 AMD EPYC 9V74
shared worker, CPU0 pinned, native Cranelift Release. The exact baseline and
candidate permutation functions were loaded as source-local modules through
this driver, with the same public function and private helper names. The sole
candidate behavior change handles zero alongside invalid sizes and returns the
one empty permutation without building a bitmap. Healthy nonzero sizes retain
one size-check branch. These are
focused measurements alongside the [latest broad baseline](../baseline-2026-10-28.md),
not a new full-suite or cross-platform performance claim.

Twenty measured alternating pairs follow two warmup pairs. All output counts
and shapes pass. Times are separate medians; the ratio is the median paired
after/before value, so dividing the displayed times need not reproduce it.

| Input length / size | Before ns/call | After ns/call | Paired ratio |
| --- | ---: | ---: | ---: |
| 1,000,000 / 0 | 892,936 | 330 | 0.0004 |
| 100,000 / 0 | 92,664 | 35 | 0.0004 |
| 5 / 0 | 31.90 | 8.77 | 0.275 |
| 0 / 0 | 24.09 | 8.97 | 0.375 |
| 1 / 1 | 57.12 | 56.61 | 0.999 |
| 5 / 1 | 184.73 | 188.01 | 1.023 |
| 5 / 2 | 702.38 | 697.69 | 0.988 |
| 5 / 5 | 9,597.35 | 9,538.82 | 0.996 |

The short post-change large-input batches include timer and first-allocation
overhead; their sub-microsecond values are not a latency guarantee. Nonzero
controls are noisy. The positive 5/1 median is disclosed, not claimed as a gain
or an established regression. A longer confirmation uses 1.5M calls per process,
36 measured triples after two warmups, cycling all six orders of baseline,
the same baseline binary again (A/A), and candidate. The 5/1 paired median is
0.990, versus A/A 0.986; respective interquartile ranges are 0.919–1.088 and
0.915–1.028. This does not establish a nonzero-path regression.

Process-level minor faults for the 1M/0 workload fell from a median 2,671 to
2,425, measured with `getrusage(RUSAGE_CHILDREN)`; input construction remains
included in those process counts. Valgrind/perf are unavailable, so no
instruction-count claim is made. The source establishes removal of the
linear bitmap initialization. Raw qualification samples are uncommitted.
