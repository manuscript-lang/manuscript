# Compare Decimal coefficients without allocating BigInts

Measured 2026-10-31 against main
`d4a94aa9283348133542078e22ccaa3b2c9dc348`. Decimal comparisons formerly constructed
BigInts from both coefficients, allocating for nonzero values and sometimes for
scaled copies.
The candidate compares signed i128 coefficients directly when their quantum
matches or signs differ. Otherwise it compares leading decimal exponents first;
when those match, aligning the shorter coefficient needs at most 33 places and
at most 34 digits. Unsigned checked arithmetic also handles raw Rust coefficient
bits. No representation, API, ABI, rounding, or valid Decimal ordering change.

The five measured comparison classes improve in every paired phase, about
**1.6–3.4x**. Fixed common-path controls do not reproduce the material regression
that rejected the separate truncation experiment. This is retention evidence
for these workloads, not an all-path no-regression or Rust-parity proof. Final
combined-main replay remains required after merge.

## Configuration and protocol

Linux x86_64, AMD EPYC 9V45 under KVM, five visible CPUs, four-CPU cgroup quota,
16 GiB memory limit. Every producer inherited CPU 0 affinity. Rust/Cargo 1.99.1,
num-bigint 0.5.1. Native archives used `cargo xtask runtime` (release opt-level 3,
debug 0, musl). Both MS variants used the same unchanged compiler, explicit
**`MS_BACKEND=cranelift`**, `--build-type Release`, and preserved before/after
`MS_RT_LIB` archives. This is Cranelift Release evidence, not LLVM or another
platform. Rust used release opt-level 3, overflow checks and frame pointers,
host GNU target. [artifacts.json](artifacts.json) records source, compiler,
archive, executable and harness hashes. No build or other benchmark ran
concurrently; shared-host noise remains a limitation.

The [primary matrix](results/paired.jsonl) has five classes at counts 1/8/1M,
eight rotating/reversed phases plus warmup, with before/after/Rust/baseline A/A:
540 invocations, 480 measured. The unchanged existing
[conversion controls](results/conversion-controls.jsonl) cover all 14 identities
in eight balanced pairs plus warmup: 252 invocations, 224 measured. The
[long controls](results/long-controls.jsonl) were fixed before measuring, including
25,000,001 negations at two seeds, Int/UInt64 conversion, conversion+truncation,
and add/round/truncate, with baseline/candidate A/A and eight balanced phases:
216 invocations, 192 measured. All **1,008 invocations** succeeded; 896 are measured.
All samples/outliers are retained. Independent review checked exact expected
identity/phase sets, outputs, timing bounds, hashes, and the retention assessment.
No further timing session or placement tuning was used.

## Comparison results

Internal ns/iteration, median [minimum–maximum], one million iterations. Times
include indexed input access, comparison, checked weighted checksum and loop
arithmetic. Setup, parsing, validation, startup and output are outside timers.
Paired ratios are medians of candidate/baseline within each phase.

| Class | Before | Candidate | Rust reference | Paired ratio | Baseline A/A |
| --- | ---: | ---: | ---: | ---: | ---: |
| Common integers | 18.84 [18.26–20.26] | 9.58 [9.44–9.81] | 2.10 [2.02–2.16] | 0.509 | 1.002 |
| Signs and zero | 16.48 [15.63–17.23] | 10.11 [9.94–11.88] | 2.94 [2.84–3.16] | 0.625 | 0.994 |
| Exponent gaps | 46.70 [46.27–48.52] | 21.52 [21.00–21.68] | 11.03 [10.84–11.18] | 0.460 | 0.994 |
| Coefficient alignment | 80.84 [79.92–82.18] | 24.04 [23.54–24.61] | 12.65 [12.39–13.12] | 0.298 | 0.995 |
| Large/boundary values | 34.35 [33.74–35.47] | 13.13 [12.78–13.36] | 4.43 [4.41–4.58] | 0.379 | 1.001 |

Rust uses a custom exact i128 coefficient/exponent representation and equivalent
integer comparison, with per-iteration `black_box` input. `ms-std-decimal` and
num-bigint prepare/validate values outside timing; `rust_decimal` is not used
because its 96-bit coefficient/28-digit precision differs. Rust indexes a vector
of pairs, whereas MS indexes two lists, so these are full-workload ratios
including layout/indexing and native-call overhead, not isolated helper costs.
Manuscript remains about 1.9–4.6x slower than this Rust workload after the change.

## Common-path controls and limits

Long-control median ns/iteration and paired ratios:

| Control | Before | Candidate | Paired ratio | Baseline A/A | Candidate A/A |
| --- | ---: | ---: | ---: | ---: | ---: |
| Negate, seed 12345 | 1.481 | 1.476 | 0.997 | 1.000 | 1.003 |
| Negate, seed Int minimum | 1.463 | 1.477 | 1.006 | 1.000 | 0.995 |
| Int conversion | 3.107 | 3.088 | 0.997 | 1.003 | 0.997 |
| UInt64 conversion | 2.621 | 2.596 | 0.990 | 0.990 | 1.004 |
| Conversion + truncate stream | 22.149 | 22.811 | 1.017 | 1.002 | 0.978 |
| Add + round + truncate | 326.053 | 326.060 | 0.996 | 0.991 | 0.992 |

The longer stream is 1.7% slower in the paired median (6/8 slower), with paired
range 0.967–1.049 and comparable same-binary variation; its initial shorter
control instead measured 0.962. This is uncertain/noisy, not proof of equivalence.
The initial UInt64 control's 1.021 ratio was not reproduced by the longer control,
whose 0.990 ratio matches baseline A/A. Tiny/one-shot rows include timer overhead
and support no single-call speed claim. No allocation counter or RSS measurement
was collected. The comparator's eliminated BigInt construction follows from
source; a memory improvement is not measured.

## Correctness and checks

`inputs.json` owns all input pairs. The runner checks both MS lists and Rust pair
literals against it. Each producer validates every full comparison result against
constants independently computed with Python Decimal comparison before timing.
Every timed result contributes to a checked weighted checksum. Python verifies
producer success, empty stderr, exact identity/count/checksum, timing bounds,
and complete phases before summaries.

- `fixed_width_comparison_matches_exact_alignment` compares against exact BigInt
  alignment, both operand orders, 138,000 randomized sign/gap cases, 2,000 directed
  same-leading cases, every digit gap, sign/zero boundaries, raw i128 endpoints,
  exponent extremes, nonnormalized equivalents and checked-alignment overflow.
- `decimal-comparison-alignment.ms` checks all 34 alignment distances, both signs
  and operand orders, maximum and minimum Decimal exponents. It passes Debug
  and explicit Cranelift Release. Five existing Decimal source fixtures also pass.
- `cargo nextest run --locked -p ms-std-decimal -p ms-std-bigint -p ms-std-math`:
  19 tests passed, zero skipped; cargo-nextest 0.9.150.
- Workspace Rust formatting and Clippy with warnings denied, repository checks,
  Python syntax, dataset/oracle checks, and independent static/data review pass.

Broad workspace execution/conformance is left to CI because this campaign lane
excludes lifetime, ownership, backend, Windows and networking investigations.
Those broad local gates are not claimed as passed. Related correctness PRs
#2059/#2067 touch BigInt power/shift contracts; no overlapping edit is included.

## Fresh-main composition replay

The branch was combined with main `3cfde58b6216ae4db54aeb3ae4e22ee7d527e323`
(candidate `2fef66f08e0bf2db2ae6179d46ad318c7eb01524`). Both native archives
were rebuilt sequentially at the same build path, and both MS workloads used one
saved unchanged compiler. The entire fixed 1,008-invocation protocol was repeated,
with [all raw results and hashes](results/combined-3cfde58b6/paired.jsonl)
([controls](results/combined-3cfde58b6/conversion-controls.jsonl),
[long controls](results/combined-3cfde58b6/long-controls.jsonl),
[artifacts](results/combined-3cfde58b6/artifacts.json)). This is the PR composition,
not yet a post-merge final-main claim.

Comparison paired ratios remain 0.519 common, 0.641 signs, 0.462 gaps, 0.298
alignment and 0.374 large/boundary, with primary A/A 0.997–1.019. Longer common
ratios are 0.993/1.000 negation, 1.001 Int, 0.982 UInt64, 1.004 conversion stream,
and 0.989 add/round. Baseline/candidate A/A variation remains visible; these
controls reproduce the comparison gains without establishing universal
performance equivalence. Nineteen numeric nextest tests, six source fixtures,
Release alignment, workspace formatting and Clippy pass on the combined tree.

## Further numeric discovery: residual gaps

A bounded independent sweep checks BigInt factorial and a fixed-integer linear
congruential recurrence against Rust on the same combined state. It uses nine
identities across zero/tiny/common/large factorial inputs and a million-step
integer recurrence, ten rotating/reversed phases plus warmup, before/after,
idiomatic Rust, a borrowed-BigInt Rust diagnostic and baseline A/A. All
**495 invocations** passed independent Python full-result and weighted-checksum
validation; [raw data](discovery/results.jsonl), [source](discovery/main.ms),
[Rust](discovery/rust/src/main.rs), [harness](discovery/repeat.py), and
[hashes](discovery/artifacts.json) are preserved. Each full canonical factorial
result (up to 4,115 digits) is validated outside timing before its digest is
recorded. All timed iterations contribute to the checksum. The two MS binaries
are byte-for-byte identical, so this also controls unaffected numeric execution.

Batched medians, ns per complete factorial/recurrence result, including normal
remainder/checksum/loop handling:

| Workload | Repeats per producer | MS before | MS candidate | Rust idiomatic | Rust borrowed diagnostic |
| --- | ---: | ---: | ---: | ---: | ---: |
| Factorial 0 | 10,000 | 19.16 | 19.14 | 5.84 | 5.84 |
| Factorial 20 | 100,000 | 371.44 | 369.52 | 51.73 | 78.36 |
| Factorial 1,000 | 200 | 62,655 | 62,713 | 35,921 | 52,965 |
| Factorial 1,500 | 100 | 130,721 | 129,123 | 83,039 | 123,178 |
| Integer recurrence, 1M steps | 5 | 3,354,321 | 3,351,121 | 2,624,924 | 2,624,185 |

Both factorials use exact unbounded signed integers from num-bigint 0.5.1 and
the same ordered multiplication algorithm/inputs/results. Idiomatic Rust uses
owned `MulAssign<i64>`; the diagnostic materializes each factor as BigInt and
uses borrowed multiplication, closer to the MS public operation shape. The Rust
loop selects those forms with a stable Boolean branch, so these full-workload
ratios include that dispatch rather than establishing isolated multiplication
latency. The two Rust labels execute the same LCG code.
Fixed integers use checked i64 arithmetic in both languages; inputs
stay in range. Rust's per-iteration bound passes through `black_box`.

Tiny BigInt factorial remains much slower than idiomatic Rust; the fixed-integer
recurrence remains about 1.28x slower. Reducing native-call/representation work
or investigating generated-loop overhead would enter this lane's inherited
native ABI, ownership, or backend exclusions. Those mechanisms were not
investigated, reproduced as separate defects, or patched. These are unresolved
scope boundaries, not proof that the remainder of the numeric lane is clean.
No power or shift operations overlap correctness PRs #2059/#2067.

To reproduce after the main builds in [Reproduce](#reproduce):

```sh
cargo build --release --locked --manifest-path bench/perf/decimal-comparison/discovery/rust/Cargo.toml --target-dir /tmp/discovery-rust
MS_BACKEND=cranelift MS_RT_LIB=/tmp/compare-base/target/ms-native/libms_native.a "$ms_compiler" build bench/perf/decimal-comparison/discovery/main.ms --build-type Release -o /tmp/discovery-before
MS_BACKEND=cranelift MS_RT_LIB="$PWD/target/ms-native/libms_native.a" "$ms_compiler" build bench/perf/decimal-comparison/discovery/main.ms --build-type Release -o /tmp/discovery-after
taskset -c 0 python3 bench/perf/decimal-comparison/discovery/repeat.py /tmp/discovery-before /tmp/discovery-after /tmp/discovery-rust/release/numeric-discovery-control > /tmp/discovery.jsonl
```

## Reproduce

Use isolated baseline/candidate worktrees, build both native archives, then use
one baseline-built compiler for both workloads. In a checkout of this change:

```sh
base=d4a94aa9283348133542078e22ccaa3b2c9dc348
evidence="$PWD/bench/perf/decimal-comparison"
control_source="$PWD/bench/perf/decimal-conversions/main.ms"
git worktree add --detach /tmp/compare-base "$base"
(cd /tmp/compare-base && cargo xtask runtime && cargo build --release --locked -p ms-cli)
cargo xtask runtime
cargo build --release --locked --manifest-path "$evidence/rust/Cargo.toml" --target-dir /tmp/compare-rust
ms_compiler=/tmp/compare-base/target/release/ms
MS_BACKEND=cranelift MS_RT_LIB=/tmp/compare-base/target/ms-native/libms_native.a "$ms_compiler" build "$evidence/main.ms" --build-type Release -o /tmp/compare-before
MS_BACKEND=cranelift MS_RT_LIB="$PWD/target/ms-native/libms_native.a" "$ms_compiler" build "$evidence/main.ms" --build-type Release -o /tmp/compare-after
MS_BACKEND=cranelift MS_RT_LIB=/tmp/compare-base/target/ms-native/libms_native.a "$ms_compiler" build "$control_source" --build-type Release -o /tmp/control-before
MS_BACKEND=cranelift MS_RT_LIB="$PWD/target/ms-native/libms_native.a" "$ms_compiler" build "$control_source" --build-type Release -o /tmp/control-after
```

After builds finish, with no concurrent CPU-heavy work and an available CPU:

```sh
taskset -c 0 python3 bench/perf/decimal-comparison/repeat.py /tmp/compare-before /tmp/compare-after /tmp/compare-rust/release/decimal-comparison-reference > /tmp/paired.jsonl
taskset -c 0 python3 bench/perf/decimal-conversions/repeat.py /tmp/control-before /tmp/control-after 8 > /tmp/conversion-controls.jsonl
taskset -c 0 python3 bench/perf/decimal-comparison/long_controls.py /tmp/control-before /tmp/control-after > /tmp/long-controls.jsonl
```

The main repeat count must be a positive multiple of eight. Use a writable
`XDG_CACHE_HOME` if the home directory is read-only. Before claiming integration,
repeat all affected controls against final combined main and perform a fresh
numeric discovery pass; isolated measurements do not establish that state.
