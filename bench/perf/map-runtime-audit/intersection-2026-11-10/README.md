# Empty-right Set intersection investigation, 2026-11-10

This is a distinct candidate from an earlier rejected insertion experiment,
whose runtime source was restored before this investigation.
The local change returns an empty Set with exactly the left stored creator
descriptor when the right operand is empty. The existing path scanned the left
slots even though every right membership probe returned before hashing. The
nonempty path, ordering, callbacks, ownership and memory model are unchanged.

Baseline: `6c9260f8c39a45c55a7f59f7df28bf373b6f97df`. Candidate: that revision
plus [the retained patch](candidate.patch). Both normal `make build` builds used
Rust 1.99.1 and generated LLVM Release producers on AMD EPYC 9V74, Linux x86-64.
All timed producer runs were pinned to CPU 0; no builds or other benchmarks ran
concurrently. This does not isolate host scheduling or CPU frequency changes.
The [manifest](manifest.json) retains binary/source hashes and build metadata.
The latest aggregate [baseline](../../baseline-2026-10-28.md) and newer
[results](../../results-2026-11-09.md) use a different machine; no cross-machine
performance ratio is claimed.

## Reproduction and correctness

The [minimal reproduction](../empty-intersection-repro.ms), built on the baseline,
runs 1,000 intersections and checks checksum zero. Five trials took a median
12,208 ns with one left member and 183,760,633 ns with 65,536 members. The
[raw samples](baseline/repro-samples.txt) include every run.

The [integer producer](../intersection.ms) and [owned-string producer](../intersection-strings.ms)
independently construct the exact ordered expected output before timing and
validate the result. Timed iterations consume the output and check its checksum.
The string workload additionally looks up each returned key in a metadata Map.
The [Manuscript driver](../../../tools/map_intersection_audit.ms) independently
checks a closed-form checksum, successful exit, empty stderr and positive time.
It retains both internal elapsed time and whole-process wall time.

Every case has a warmup (`trial=-1`, excluded from summaries). Version order
alternates for each paired trial. Sizes are 0, 1, 8, 128, 4096 and 65536; patterns
are empty right, equal operands, disjoint operands, one shared member and a
left operand with holes. Union and difference are neighboring controls.

- [Baseline](baseline/samples/samples.csv): 90 cases, five trials and a warmup.
- [Integer pairs](paired/samples.csv): 90 cases, ten pairs and warmups, 2M work.
- [Longer flagged controls](focused): eight cases, twenty pairs, 20M work.
- [String pairs](strings/samples.csv): 30 intersection cases, twelve pairs, 2M work.
- [Map controls](paired-maps.json): 52 existing lookup/overwrite cases, six pairs.
- [Long Map controls](focused-maps.json): 18 cases, twelve pairs; and a
  [reversed ordering pass](reversed-maps.json) over the original 52 cases.
- [Isolated Map confirmation](map-confirm): six cases, twenty-four pairs;
  **version 0 is candidate and version 1 baseline** in these CSVs. Exact
  arguments and labels are in the manifest, with a [summary](map-confirm-summary.csv).
- [Summary](summary.csv): all integer and String cases, including controls.

## Results and limits

For the integer empty-right workload, median paired candidate/baseline ratios
for internal time at sizes 0/1/8/128/4096/65536 were
0.991/1.000/0.404/0.030/0.00105/0.00027. The corresponding whole-process ratios
were 0.990/1.003/0.465/0.159/0.159/0.434. Large internal gains do not translate
directly into application speedups: startup, construction and cleanup remain.

Owned-string empty-right ratios at the same sizes were
0.928/0.721/0.311/0.025/0.0071/0.242 internally and
0.931/0.733/0.377/0.165/0.323/0.842 for the whole process. No String nonempty
control exceeded a 1.03 median paired ratio in the twelve-pair run. These are
synthetic filtering and metadata-lookup workloads, not an existing application.
Internal times include result materialization and consumption, metadata lookup
for String keys, and may include last-use cleanup of operands or metadata.
At 65,536 entries the candidate String batch takes about 1.936 ms, versus
1.50 microseconds for the integer batch. Exact cleanup placement was not
investigated; these are workload costs, not isolated intersection latency.

Eight initial integer algebra controls flagged 3–6% slowdowns. In longer trials
their median paired ratios ranged from 0.981 to 1.012, with mixed directions
across samples. Initial Map-control flags reached 4–12%, but did not persist
at that magnitude in longer or reversed-order trials. Isolated confirmation
ratios for Int overwrite/128, String lookup/128/prefix16, String lookup/4096/
prefix0, String lookup/4096/prefix4096, String overwrite/4096/prefix0, and String
overwrite/65536/prefix256 were respectively
1.0005/0.9946/0.9914/1.0067/1.0046/1.0272. The last case was slower in 13 of 24
pairs; a small residual effect remains uncertain. All unfavorable samples are
retained. The Map executable sections are not byte-identical between builds,
so code identity is not used to dismiss these observations. No universal
performance-parity or regression-free claim is made.

The previous inventory reference remains non-comparable because it contains
removed syntax. It was not rewritten or counted as passing application evidence.
Instruction counts and page faults were not collected: perf and valgrind are
absent from PATH. No microarchitectural cause or universal speedup is claimed.

## Validation and publication

All 21 map unit tests and 16 source collection tests pass, including new tests
for zero callbacks, retained storage, exact creator identity, later insertion,
unchanged inputs and owned-string independence. Independent Astra source review
found no correctness blocker and requested String and longer control trials.
Formatting, workspace Clippy, ABI, repository and benchmark checks passed.
The full runtime suite passed (214 unit tests and 12 integration tests), as did
docs, licenses and packaged-distribution checks. `make verify-full` stopped at
missing nextest. Its official download returned HTTP 403; installation was
stopped without retry or alternate route. Initial conformance/e2e invocations
failed because the debug CLI normally built by the unit stage was absent;
that prerequisite must be built before rerunning those checks. Book validation
stopped at missing Hugo. Leak checks, exact-head CI and platform validation
remain incomplete. See [independent review](review.md). No merge is claimed.
