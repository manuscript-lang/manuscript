# Build RFC 3339 text in the output string

`Timestamp.to_string()` grew its output from an empty String and, for fractional
seconds, rendered into another String before copying the trimmed fraction. The
change reserves the valid UTC maximum of 30 bytes, writes the fraction directly
into the output, and removes trailing zeros before appending `Z`. Capacity remains
growable; padding and fractional text are unchanged. Allocation removal follows
from source; no allocator, RSS or instruction-count measurement is claimed.

## Pinned release measurements, 2026-10-31

Baseline is `6f7a272158d4baf3c007a3323a4f7d556a797193`, including the separately
reviewed token-cache optimization. The only additional production change is in
`core_time::to_string`. Before/after use one compiler, one workload, and separately
supplied native archives. This experiment does not modify the earlier token scan.

Host/toolchain match [the token-format experiment](../calendar-format/README.md):
Linux x86-64 6.18.57, AMD EPYC 9V74, CPU 0 affinity, four-CPU quota, 16 GiB memory
limit; Rust/Cargo 1.99.1; explicit `MS_BACKEND=llvm`, pinned LLVM 23.1.1 directory,
Release programs and musl release native archives. No local build/test ran during
measurements. Shared-host noise remains. Rust uses host libc, release optimization
and checked workload arithmetic; dependency arithmetic matches native release.

The Rust control shares the unchanged `civil_of` conversion and renders the same
fields and fractions into a growable String. Timestamps and expected outputs are
constructed before timing. **Every output is checked inside timing**, and its
length contributes to a checked checksum. Python independently constructs the
expected strings, including unequal-length pairs. Setup, process startup and
final printing are outside the inner timer. Reported times are formatting plus
validation; raw child CPU deltas cover the entire process.

Each session includes a separate warmup, balanced producer order and rotating
case order. Nothing is removed from the data. The main session has 12 repeats,
200,000 operations per sample and an identical-baseline A/A label.

| Input | Before ns/op | After ns/op | Rust ns/op | Paired after/before | Paired A/A | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Whole seconds | 184.24 | 154.26 | 134.98 | 0.837 | 1.002 | 12/12 |
| Milliseconds | 221.11 | 180.20 | 159.85 | 0.803 | 1.002 | 11/12 |
| Nine-digit fractions | 221.64 | 173.31 | 156.37 | 0.800 | 0.998 | 12/12 |
| Leading fractional zeros | 243.20 | 189.28 | 170.89 | 0.774 | 0.988 | 12/12 |
| Year limits | 213.17 | 173.76 | 157.43 | 0.829 | 0.996 | 12/12 |
| Mixed lengths around epoch | 210.94 | 170.52 | 152.26 | 0.812 | 1.000 | 12/12 |

These are medians; paired ratios are computed per trial before taking their
median. All individual distributions and minima/maxima remain in
[candidate.jsonl](results/candidate.jsonl). Rust remains faster; this is no
universal parity or cross-platform claim.

## Unchanged controls

The full ten-case token-format suite was repeated against both archives, with 12
balanced repeats and A/A. Paired medians ranged from 0.978 to 1.019. Initial small
slowdowns for repeated tokens and long literal text prompted a predeclared longer
session: 16 repeats, two million operations before the same length scaling, and
the literal, repeated-token and long-literal cases. The longer result was:

| Control | Before ns/op | After ns/op | Paired after/before | Paired A/A | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Literal | 131.82 | 133.86 | 1.018 | 0.987 | 6/16 |
| Repeated tokens | 1112.87 | 1119.63 | 0.999 | 0.997 | 8/16 |
| Long literal | 11887.54 | 11835.97 | 0.989 | 0.998 | 10/16 |

The repeated-token and long-literal slowdowns did not persist. Small literal
cost remains uncertain; the 1.8% paired slowdown and A/A drift are retained rather
than claiming every path is unchanged. No alignment padding or backend tuning
was attempted.

An additional session compares the token-cache baseline with the original
`d4a94aa9283348133542078e22ccaa3b2c9dc348` archive on all six RFC 3339 workloads.
Its paired ratios are 1.003, 0.992, 1.002, 1.003, 0.970 and 1.007 respectively;
A/A ranges from 0.978 to 1.004. It does not establish an unrelated RFC 3339 gain
from the first change.

All **1,089 invocations** in the four committed datasets pass exact producer
identity/count/checksum/output validation:

- [Main candidate](results/candidate.jsonl): 312 invocations.
- [Full unchanged controls](results/calendar-controls.jsonl): 390.
- [Long controls](results/calendar-long-controls.jsonl): 153.
- [Token-cache RFC 3339 controls](results/token-cache-rfc-controls.jsonl): 234.

The initial exploratory baseline remains locally at
`.artifacts/timestamp-format/baseline.jsonl`; it predates the expanded metadata
and is excluded from these headline counts. Binaries and archives stay local.

## Correctness and review

`timestamp_text_matches_previous_renderer` checks 5,120 exact comparisons with
the previous renderer and parse roundtrips. `timestamp-text.ms` checks 50 public
roundtrips and five explicit boundary/fraction outputs in Debug and Release.
All 11 time-crate tests, the prior token-format source tests, 18 selected time
conformance fixtures, workspace Clippy, formatting and repository checks pass.
Full workspace and unrelated conformance execution were not run under the
campaign's excluded investigation scopes. Public signatures and output rules
are unchanged. Direct out-of-contract Rust `Ts` values retain growable output by
inspection but are not part of the new test matrix.

Independent Sol 6.1 read-only review found no code/harness blocker and independently
verified all 1,089 samples, published medians/ratios/win counts, source and binary
identities, and both archive hashes. Fresh combined-main replay remains separate
from these local results.

## Reproduce and artifact provenance

Build the baseline archive at the named revision in an isolated worktree. Build
the candidate archive with `cargo xtask runtime`; use the same compiler and final
`main.ms` for both, setting `MS_RT_LIB` to each archive. Use explicit Release and
the pinned LLVM directory, as in the token-format protocol. Build the Rust
control with `cargo build --release --manifest-path
bench/perf/timestamp-format/rust/Cargo.toml`, then run:

```sh
python3 bench/perf/timestamp-format/repeat.py \
  --producer before=/tmp/timestamp-before --producer after=/tmp/timestamp-after \
  --producer rust="$PWD/bench/perf/timestamp-format/rust/target/release/timestamp-format-control::rust" \
  --producer before-AA=/tmp/timestamp-before --repeats 12
```

Raw current-source hashes describe the candidate, not the older baseline
binaries. The Rust control binary was built at the baseline before the production
edit and calls unchanged civil conversion. The compiler is the same one named in
the token-format report. Native archives and workload identities:

```text
before archive c15936c3b6cfdbd2e86860670542b293dccef78ec11829c57a5c546fed4d87c8
after archive 05524854b777e2ede61f5b830eaa3f6d38e1c57d0c7f49b1b5d8b14ef8438cce
before program 015ea1047d0b65e3d7c6499c91391e2ef789331a081f4c98ce36b7708861a94e
after program 73c5db6dc0bb3493eaf921ccbcfd6f799d35c355e78fb5f2ebf416dc5b536c37
Rust program 00178af87fda2c7d44a31f9c2194ae03368f3bc0cc32cc5eb0d3074bc95a6ead
calendar before e78268bc4e24b834deec086c241e03e7f40a2b2312f9c2fe09c06121d8fe4d26
calendar after 94e378ef660e1055379f5b6eb1ef85d58e5304127989391c9f459a1c961e8875
original-d4 RFC program 5868b245fee8b1a98a93691e5136f4ec042e9687959416f3a59abb086c8f85e6
```
