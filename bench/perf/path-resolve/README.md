# POSIX path resolution

This suite times native LLVM Release calls to `posix().resolve` with ordinary
relative tails, long tails, dot segments, a later absolute reset, invalid NUL
input, and an unchanged Windows control. Input construction and a warm call are
outside the timer. Each timed result is compared with the warm result, and its
length (or error count) contributes to the printed checksum. The called path
conformance tests independently pin the expected results and error identities.

Build the repository runtime and release compiler at each revision, then build
`main.ms` using `target/release/ms build bench/perf/path-resolve/main.ms
--build-type Release -o /tmp/path-resolve/base` at the baseline and the same
command with `-o /tmp/path-resolve/new` at the candidate. Copy this benchmark
source to the baseline checkout; it does not change the library. Run:

```sh
BENCH_CPU=4 python3 bench/perf/path-resolve/run.py /tmp/path-resolve /tmp/samples.json
```

The standard-library baseline dated [2026-10-28](../baseline-2026-10-28.md)
contains `path.join_normalize`, but no `resolve` case. This is a focused new
before/after suite, not an overall standard-library or native-language parity
claim.

## 2026-11-12

Baseline: `ff4ce5edff87e46edf1f1f105bc93cd1b6236217`, rebuilt native runtime and
release compiler. Linux x86_64, AMD EPYC 7763, CPU 4, LLVM Release; 21 alternating
pairs per case with no concurrent builds. No samples were removed from those
final paired runs. An initial A/A run overlapped a rebuild and was excluded; the
committed A/A run was repeated without concurrent builds. Raw samples,
A/A samples, page faults and executable SHA-256 values are in
[results-2026-11-12](results-2026-11-12/). Hardware instruction counters and
Callgrind were unavailable in this environment.

Median nanoseconds per call, including result equality and checksum work:

| Case | Parts | Baseline | Candidate |
| --- | ---: | ---: | ---: |
| Relative | 0 | 194.10 | 176.99 |
| Relative | 1 | 149.38 | 152.52 |
| Relative | 4 | 353.96 | 323.56 |
| Relative | 32 | 2,551.83 | 1,325.01 |
| Relative | 256 | 28,628.22 | 8,974.73 |
| Relative | 2,048 | 882,604.47 | 68,394.50 |
| Dot segments / Unicode | 4 | 664.58 | 609.90 |
| Dot segments / Unicode | 256 | 35,400.73 | 18,333.53 |
| Later absolute reset | 256 | 26,300.53 | 1,358.29 |
| Invalid NUL | 256 | 1,210.52 | 1,235.69 |
| Unchanged Windows | 4 | 1,761.26 | 1,742.37 |
The one-part +2.1% difference is comparable to A/A variation: identical baseline
executables measured 153.83 and 151.66 ns (-1.4%) in the same protocol; the
unchanged Windows A/A control differed by +2.6%. These shared-host measurements
do not establish a one-part speedup. Separate seven-pair process fault checks
record no major faults; the raw file retains minor faults for small and large
cases.

Rejected experiments: a byte builder that inserted redundant separators measured
150→313 ns for one part and 351→618 ns for four. Preserving separators narrowed
those regressions to 149→167 and 356→376 ns. The string builder avoids the
bytes-to-UTF8 conversion. Its first form still regressed all-empty tails by
17–19%; the final scan records whether a surviving nonempty relative tail exists
and avoids constructing an unused builder. No size threshold or special benchmark dispatch was
added.

Correctness: 10,368 combinations of six bases and three parts chosen from twelve
values were compared exactly against the original resolver in one LLVM Release
executable. Values included empty parts, repeated/leading/trailing separators,
dots, Unicode, NUL and POSIX backslashes. The original reference module's unused
glob operation was stubbed because app modules cannot import the private native
binding; the resolver and all its callees were unchanged. The public called
fixture covers invalid bases and NUL even in a superseded part, absolute resets,
root-only results, Unicode and 512-part tails; LLVM and Cranelift pass.

All-empty-tail controls run the unchanged baseline resolver and current resolver
in one LLVM Release executable, through matching function-value loops. A temporary
reference module is generated from the baseline revision; only its factory name
and unused private glob binding are adapted. Reproduce with:

```sh
BENCH_CPU=4 python3 bench/perf/path-resolve/empty-controls.py target/release/ms /tmp/empty.json
```

The final 21-pair medians (baseline → candidate ns/call) are 192.27→177.28
for zero parts, 199.97→187.95 for one empty part, 225.09→217.37 for four,
494.04→477.80 for 32, and 2,582.85→2,503.63 for 256. Raw before/after diagnostic
samples are retained separately; these include function-value invocation and are
not interchangeable with the main harness latencies.
