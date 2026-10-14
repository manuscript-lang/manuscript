# Issue87: source boundary and workload acceptance

This implementation integrates checked native scalar storage/calls with the
shared List runtime. It covers the reported loop, call, at/unwrap and exact
128×128×50 Game of Life workload; a single microbenchmark is not the acceptance
criterion. [Raw samples and provenance](results/issue87/provenance.json) identify
main8001f48e, candidate dbf8cb03, provider a0c29276 and all inputs/generated hashes.
Publication92a73898 has the same source tree as dbf8cb03. Later provider7727cc39
adds strict fresh-state initialization; these workload samples do not use its
initialization setters. Keep that distinction when assessing #147's literal gate.

These are three serial100ms smoke samples with the pinned Go1.25.1 SDK on a
shared Linux AMD64 host (GOMAXPROCS4). Timings below are approximate medians,
not paired confidence estimates. Allocation counts and deterministic output
parity are separate evidence. Handwritten Go omits language faults,
cancellation, source frames and call-depth accounting.

| Actual generated workload | Main time / allocs | Candidate time / allocs | Handwritten Go time / allocs |
| --- | --- | --- | --- |
| Loop1024 (`total + index % 7`) | 40.9µs /1706 | 3.14µs /1 | 0.95–1.01µs /0 |
| Known calls1024 | 96.3µs /2730 | 23.8µs /1 | 1.77–1.85µs /0 |
| At/unwrap1024 | 117µs /3841 | 16.6µs /1 | 2.10µs /0 |
| Match-at1024 | See raw main samples /3841 | 19.4µs /1 | 2.02µs /0 |
| Life128×128×50 | 738ms /~13,989,340 | 90.5ms /~1073 | 9.02ms /51 |

The first three candidate workloads allocate8B only for their final boxed
result. Life allocates~24.93MB, versus main~593.40MB and Go~6.68MB; List append
growth and runtime checks remain visible. At/unwrap and every tested Life size
and generation count, including exactly128×128×50, pass the handwritten checksum
oracle before benchmarking. Named/captured64K sort controls use15/21 allocations,
with no per-comparison argument/result boxes.

The unchanged ordinary callback fixture is an independent gate:

|64K generated List workload|Main allocs /bytes|Candidate allocs /bytes|
|---|---|---|
|Append|130681 /~6.59MB|29 /~2.51MB|
|Index|327424 /~6.81MB|1 /8B|
|Iterate|65535 /~524284B|1 /8B|
|Ordinary source `for_each`|131090 /~1.574MB|130925 /~1.048MB|
|Sort|~2,225,800 /~52.65MB|15 /~525192B|
|Clone|2 /1048624B|2 /524432B|

Storage-only callbacks regressed to196461 allocations/~2.097MB. Typed source
loops did not clear that gate. The parent-approved generated non-retention proof
and invocation-local buffer now clear the source callback allocation regression,
while arbitrary Go callbacks retain fresh arrays. Individual Values may still
escape through a closure, record or collection. The source fixture exercises
retained closures, generic/captured loop bindings and nested/first-class callbacks;
runtime controls exercise retained argument arrays and same-callable reentry.

Two costs remain explicit. The low-level compatibility `Iterate` boxed control
still costs5 allocations/216B and~0.82–0.86ms, versus main1/8B and~0.26–0.28ms;
this remains a runtime-owner acceptance gate. Generated source List loops use
captured headers with native readers or `Get` and avoid this iterator machinery.
The small stored-list control retains3 allocations but160B versus main88B from
the larger authoritative List header. Identity remains0 allocations; forwarding
and copying remain1; capture improves4→3.

|Remaining issue87 scope|Acceptance|Status|
|---|---|---|
|Typed scalar locals/parameters/results and direct static calls|Checked binding identities; reordered/default/native method calls; Int64/binary64 unchanged|Implemented, native tested|
|Typed at/unwrap/match-at, captured List loops and named/captured comparators|Dynamic/generic/escaping fallback; strict Result slicing; live backing and initial length; raw comparator body/one guard|Implemented, native tested|
|Closures and first-class functions|Existing boxed payload identity, snapshots, storage, generic/captured List loops and retained callback Values|Implemented, native tested|
|Order, faults, cleanup, cancellation, recursion and profiling|Operand/receiver effects; IEEE bits; exact frames;200000-call unwind; entry/delivery checks|Native/race tested|
|Debugger|Parameters, scalar locals, watches, stepping, typed/legacy List backing and interface views|Native DAP passed; final rebuild checked separately|
|Startup record concurrency (#249)|Only real source work enables locks; timed-test runners mark before spawning; record layout unchanged|Subprocess/race tested|
|Whole workloads and ordinary callbacks|Current-main/Go output and allocation controls above|Source gates passed|
|Compatibility iterator|Explicit fixed/time regression above|Runtime-owner mitigation/acceptance pending|
|Final merge|Required exact-head hosted checks, dependency review and protected merge|Parent-owned; draft remains open|

Canonical contracts and Go migration are in
[native scalar storage/calls](../../documentation/contributing/compiler/lowering/native-scalar-calls.md)
and [List storage](../../documentation/contributing/list-storage.md).
Generated references were regenerated with no signature changes. Rebuild generated
Go with the matching runtime; use keyed Function/Implementation literals.
No numeric-width experiment, closed prototype, system-Go fallback or release is
introduced by this work.
