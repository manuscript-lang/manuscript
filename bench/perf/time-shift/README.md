# Timestamp shift arithmetic

## 2026-11-10

`Timestamp.shift` previously converted the entire timestamp to `i128` nanoseconds
and divided it by 1e9. The replacement carries nanoseconds into seconds using
`i64` quotient/remainder arithmetic. Overflowing nanosecond sums are decomposed
before addition. Raw, noncanonical fields retain their existing normalization
and range-error behavior.

On this machine, ordinary shifts took **43–46% less time**, and the overflow
controls took **30–34% less time**. A shift/format/parse pipeline was 1.5–3% faster,
but identical-binary trials vary by comparable amounts: **no reliable pipeline
speedup is claimed**. This is a few-nanosecond arithmetic optimization, not a
general application-speed claim.

### Revisions and machine

- Baseline: `d1ea6ce161ed9e5bd1af5c3b4edd8ca0b8f4b251`.
- Candidate: that revision plus the exact source diff in each raw file's
  `metadata.diff`. The final production function is the implementation in this
  PR. Later changes only strengthen tests, formatting, and evidence.
- Linux x86_64, kernel 6.18.57, AMD EPYC 9V74 guest, five visible CPUs and a
  four-CPU cgroup quota. Shared host; CPU affinity does not isolate the host.
- Rust 1.99.1 (`58cf8f9c3`, 2026-10-13), repository release settings, frame
  pointers enabled. Official Rust tools were installed independently under
  `/workspace/time-perf-tools/`; no existing toolchain or cache was modified.
- Both compilers were built with `make build`, rebuilding and embedding the
  production native archive. Both generated programs report `backend: llvm`,
  `build_type: Release`. No custom backend, allocator, target CPU or LTO flags.
- The latest whole-suite [dated baseline](../baseline-2026-10-28.md) contains
  timestamp parse/string controls but no shift case. Its other-machine timings
  are not used to claim a gain. The corresponding existing source cases were
  exercised again; their raw JSON is retained below.

### Method and correctness

[main.ms](main.ms) constructs 1, 32 or 4096 timestamps outside the timed interval.
Each process runs one untimed batch, then repeatedly processes the batch. The
baseline calibrates the repetition count to about 60 ms; both sides use exactly
the same count. [run.py](run.py) uses 12 AB/BA process pairs, shuffles case order
with seed 20261110, pins each process to CPU 0, and retains every result. No
builds or other benchmark jobs ran concurrently in this environment.

Each timed result contributes to a consumed checksum. A Python arbitrary-width
integer oracle independently computes it for every sample. Errors must be
`ERANGE`; the pipeline also checks every timestamp round trip field by field.
The program checks that repeated batches agree with its untimed batch. The
Rust differential test separately checks exact seconds, nanoseconds and status
against the original wide formula, including raw `i64` fields and extrema.

The table reports medians of each process's **timed work** divided by operations.
Raw files also retain whole-process wall time, minor/major faults, stdout,
binary/source hashes and calibration records. Setup, input generation, process
startup and compilation are excluded from the main timing. Final A/B processes
had 472–503 minor faults and zero major faults. Warm input is intentional; no
cold-cache claim is made.

This measurement runner is Linux-specific (`taskset`, `/proc`, cgroup CPU
metadata). Production arithmetic and regression tests are portable. Dynamic
instruction counting was unavailable: neither `perf` nor `valgrind` was installed.
The retained release disassembly shows the wide-division call removed from the
native wrapper; it is static supporting evidence, not a dynamic instruction count.

### Results and controls

See the [complete table](results-2026-11-10/table.md) for all 36 cases and sizes.
Representative 4096-item medians, nanoseconds per operation:

| Case | Before | After | After / before |
| --- | ---: | ---: | ---: |
| Ordinary signed subsecond shift | 10.111 | 5.492 | 0.543 |
| Zero duration | 10.420 | 5.565 | 0.534 |
| Alternating Int minimum/maximum duration | 10.032 | 6.127 | 0.611 |
| Raw negative nanosecond normalization | 10.147 | 5.548 | 0.547 |
| Positive overflowing nanosecond sum | 10.264 | 6.998 | 0.682 |
| Negative overflowing nanosecond sum | 10.194 | 7.049 | 0.691 |
| Exact-multiple overflow | 10.166 | 7.014 | 0.690 |
| Canonical nanos with maximum duration | 10.040 | 7.004 | 0.698 |
| Calendar range error | 20.817 | 17.419 | 0.837 |
| Shift → RFC3339 → parse | 214.650 | 209.802 | 0.977 |
| Unchanged parse | 26.686 | 26.953 | 1.010 |
| Unchanged format | 168.605 | 166.709 | 0.989 |

Across all sizes, unchanged parse/format medians range from 0.982x to 1.012x.
Six additional identical-baseline pairs varied by up to about 4.9% across the
suite. Pipeline medians varied from −2.46% to +2.10% in that control. The shift
gains are substantially larger; the pipeline differences are not.

An exploratory candidate retained the original wide fallback. Its positive
overflow case was 1–5.4% slower, so that version was rejected. The final overflow
decomposition improves both signs and exact multiples. All exploratory data is
retained, including the original 27-case input and candidate diffs:

- [First candidate](results-2026-11-10/first-candidate.json),
  [second candidate](results-2026-11-10/second-candidate.json),
  [preliminary input](results-2026-11-10/preliminary-main.ms.txt).
- [Final 12-pair measurements](results-2026-11-10/final.json),
  [identical-binary controls](results-2026-11-10/identical-binary.json).
- [Before native assembly](results-2026-11-10/before-shift-assembly.txt),
  [after native assembly](results-2026-11-10/after-shift-assembly.txt).
- Existing suite observations:
  [baseline parse](results-2026-11-10/baseline-parse.json),
  [candidate parse](results-2026-11-10/candidate-parse.json),
  [baseline format](results-2026-11-10/baseline-format.json),
  [candidate format](results-2026-11-10/candidate-format.json).
  These initial single-process observations were not contemporaneous pairs;
  do not interpret their differences as a regression or speedup.

The earlier oversized-fraction observation needed its own follow-up: the short
valid parse control does not exercise malformed text. After local CPU work
stopped, [stdlib-controls.py](stdlib-controls.py) ran eight AB/BA pairs of the
three existing parser cases and timestamp formatting, all pinned to CPU 0.
Each CLI invocation used 11 samples of 100 ms. The [unmodified CLI JSON reports](results-2026-11-10/stdlib-paired.json)
retain commands, operation counts, all reported statistics and binary hashes.
All cases passed. Medians of process medians, ns/op:

| Existing case | Before | After | After / before |
| --- | ---: | ---: | ---: |
| Ordinary parsing | 27.873 | 28.369 | 1.018 |
| Maximum-width parsing | 35.712 | 35.728 | 1.000 |
| Oversized-fraction rejection | 20.405 | 20.491 | 1.004 |
| Timestamp formatting | 166.161 | 165.767 | 0.998 |

The earlier apparent 9.4% oversized-fraction slowdown did not repeat in paired
trials. These unchanged-operation differences are within the observed noise
envelope; no speedup is claimed for them.

### Reproduction

Use the pinned Rust toolchain and repository build prerequisites. In separate
baseline and candidate checkouts, run `make build`; keep both resulting `ms`
binaries, which embed their respective native runtimes. Build **this same** input
with both compilers, using absolute paths as needed:

```sh
/path/to/baseline/target/release/ms build bench/perf/time-shift/main.ms -o /tmp/time-before
/path/to/candidate/target/release/ms build bench/perf/time-shift/main.ms -o /tmp/time-after
python3 bench/perf/time-shift/run.py /tmp/time-before /tmp/time-after /tmp/time-paired.json 12
python3 bench/perf/time-shift/run.py /tmp/time-before /tmp/time-before /tmp/time-identical.json 6
python3 bench/perf/time-shift/stdlib-controls.py /path/to/baseline/target/release/ms /path/to/candidate/target/release/ms /tmp/stdlib-paired.json 8
```

Check both adjacent `.ms-build.json` files for LLVM Release. The actual run used
`XDG_CACHE_HOME=/workspace/time-perf-tools/ms-cache` from first use, keeping all
new linking/optimization artifacts in the permitted workspace. No protected
cache was accessed or copied.

The existing suite commands, run for both compilers, were:

```sh
ms bench bench/perf/stdlib/numbers_bench.ms --filter time.parse_timestamp --samples 11 --time 100ms --json
ms bench bench/perf/stdlib/host_bench.ms --filter time.timestamp_to_string --samples 11 --time 100ms --json
```

Independent skeptical review checked the arithmetic proof, the compiled
regression coverage, all 1296 final A/B and A/A checksums, and binary/source hashes.
The PR's Testing section records final checks and their exact head.
