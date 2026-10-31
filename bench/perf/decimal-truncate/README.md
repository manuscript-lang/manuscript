# Rejected Decimal truncation optimization (2026-10-31)

**Rejected for production.** Replacing BigInt scaling with exact i128 arithmetic
made Decimal truncation 2.5–6.6x faster in the measured batches and improved the
common add/round/truncate control by about 11–12%. It also reproducibly slowed an
unchanged negation control by 7.7–8.5% (about 0.12 ns/iteration). That fails the
campaign's common-path regression rule. Production code is restored; the
[unapplied candidate](variants/rejected.patch) includes its differential and source
tests. No compiler/backend investigation, placement tuning, or further timing
variants were used to explain or hide the regression.

## Provenance and fixed protocol

Base main: `d4a94aa9283348133542078e22ccaa3b2c9dc348`. Linux x86_64,
AMD EPYC 9V45 KVM, five visible CPUs, four-CPU cgroup quota, 16 GiB limit.
Every producer inherited CPU 0 affinity. Rust/Cargo 1.99.1; num-bigint 0.5.1.
Native archives used `cargo xtask runtime` (release opt-level 3, debug 0, musl).
Both MS programs used **the same unchanged compiler**, explicit
`MS_BACKEND=cranelift`, `--build-type Release`, and preserved `MS_RT_LIB`
archives. This is Cranelift Release evidence, not LLVM or cross-platform evidence.
Rust used release opt-level 3 with overflow checks on, host GNU target.
[artifacts.json](artifacts.json) records binary, archive, input, source and harness
hashes. Builds and other checks finished before measurements. Shared-host noise
remains a limitation; all samples and outliers are retained.

The [main matrix](results/paired.jsonl) uses five input classes, counts 1/8/1M,
eight rotating/reversed phases plus warmup, and before/after/Rust/baseline A/A
producers: 540 invocations, 480 measured. The unchanged existing
[conversion suite](results/conversion-controls.jsonl) covers 14 identities in
eight balanced pairs plus warmup: 252 invocations, 224 measured. Its initial
negation regression triggered one predeclared
[longer control](results/long-controls.jsonl), using two negation seeds at
25,000,001 iterations plus Int, UInt64, conversion-stream and add-round controls,
eight rotating/reversed phases with before/after and A/A for both executables:
216 invocations, 192 measured. Total: **1,008 successful invocations**, 896 measured.
Independent review checked identity/phase completeness, outputs, timing bounds,
and the rejection decision. No additional timing session was used.

## Results

Internal ns/iteration, median [minimum–maximum] at one million iterations.
These measure conversion plus normal Optional handling, indexed input access,
checked weighted checksum, and loop arithmetic. Ratios are medians of paired
within-phase candidate/baseline ratios.

| Class | Before | Candidate | Rust reference | Paired ratio | Baseline A/A |
| --- | ---: | ---: | ---: | ---: | ---: |
| Integer | 26.37 [25.17–26.57] | 10.62 [10.41–11.31] | 3.78 [3.72–4.20] | 0.403 | 0.988 |
| Fraction | 71.25 [70.75–72.34] | 15.96 [15.60–17.37] | 6.40 [6.21–6.45] | 0.225 | 1.019 |
| Overflow | 34.74 [33.72–35.03] | 9.13 [8.94–9.35] | 3.02 [2.96–3.42] | 0.265 | 0.991 |
| Underflow | 84.77 [83.50–89.61] | 13.28 [13.07–13.74] | 5.48 [5.40–5.66] | 0.157 | 1.011 |
| Mixed scaling | 96.39 [95.90–99.08] | 14.57 [14.27–14.89] | 6.17 [6.15–6.32] | 0.151 | 0.997 |

The Rust reference uses the same signed i128 coefficient/exponent representation
and exact Optional i64 conversion semantics, using standard Rust integers.
`rust_decimal` was not substituted because its 96-bit coefficient/28-digit
precision differs. `ms-std-decimal` and num-bigint prepare/validate inputs outside
timing. The Rust per-iteration input passes through `black_box`; operation dispatch
is outside its monomorphized timed loop. Manuscript remains about 2.4–3.0x slower
than this equivalent custom Rust conversion workload after the rejected change;
there is no universal parity claim.

The longer common-path controls establish rejection:

| Control | Before median ns | Candidate median ns | Paired ratio | Baseline A/A | Candidate A/A |
| --- | ---: | ---: | ---: | ---: | ---: |
| Negate, seed 12345 | 1.478 | 1.594 | **1.085** | 1.004 | 0.998 |
| Negate, seed Int minimum | 1.494 | 1.610 | **1.077** | 1.002 | 0.997 |
| Int conversion | 3.132 | 3.103 | 0.993 | 0.977 | 1.002 |
| UInt64 conversion | 2.603 | 2.584 | 0.999 | 1.005 | 1.008 |
| Conversion + truncate stream | 23.494 | 10.822 | 0.459 | 0.996 | 1.002 |
| Add + round + truncate | 328.560 | 298.627 | 0.894 | 1.003 | 0.991 |

Negation was slower in 7/8 and 8/8 paired phases respectively. Its cause is
unresolved within the permitted scope. The gains do not erase that regression.
Tiny and one-shot rows retain timer overhead and justify no latency claim.
No heap-allocation counter or RSS measurement was collected. Removal of BigInt
construction follows from candidate source; memory improvement is not measured.

## Correctness and validation

`inputs.json` owns integer, fractional Int-boundary, overflow, underflow and
full-precision scaling datasets. The runner checks MS/Rust literal spellings
against it. Both producers validate every input's complete Optional result
against constants independently generated by exact Python Decimal-to-int
conversion, before timing. Every timed result contributes to a weighted checked
checksum, independently verified by Python. The harness requires successful exit,
empty stderr, exact identities/counts, timing bounds and complete phases.
Parsing, setup, validation, startup and output are outside internal timers.

Candidate checks passed before it was restored:

- `cargo test --locked -p ms-std-decimal`: 11 native tests, including exact BigInt
  differential scaling (122,000 random/sign/exponent combinations and boundaries).
- `cargo nextest run --locked -p ms-std-decimal -p ms-std-bigint -p ms-std-math`:
  19 tests passed, zero skipped (cargo-nextest 0.9.150).
- Six Decimal source fixtures passed, including both new truncation boundary
  tests; the new fixture also passed explicit Cranelift Release.
- Workspace Rust formatting and Clippy with warnings denied, repository checks,
  Python syntax, dataset/expected-value consistency, and independent static review.

Full conformance and whole-workspace execution were started then stopped to
restrict execution to the lane's permitted numeric scope. The conformance lint
reported 4,104 fixtures and zero problems before execution was stopped. Those
comprehensive gates are incomplete, not passing. There is no production patch
or final combined-main performance claim to validate from this rejected result.

## Reproduce

Create isolated baseline/candidate worktrees, apply the saved patch only to the
candidate, and use the baseline-built compiler for both variants. Start in a
checkout containing this evidence and with the repository's pinned Rust installed:

```sh
base=d4a94aa9283348133542078e22ccaa3b2c9dc348
evidence="$PWD/bench/perf/decimal-truncate"
control_source="$PWD/bench/perf/decimal-conversions/main.ms"
git worktree add --detach /tmp/decimal-base "$base"
git worktree add --detach /tmp/decimal-candidate "$base"
git -C /tmp/decimal-candidate apply "$evidence/variants/rejected.patch"
(cd /tmp/decimal-base && cargo xtask runtime && cargo build --release --locked -p ms-cli)
(cd /tmp/decimal-candidate && cargo xtask runtime)
cargo build --release --locked --manifest-path "$evidence/rust/Cargo.toml" --target-dir /tmp/decimal-rust-build
ms_compiler=/tmp/decimal-base/target/release/ms
MS_BACKEND=cranelift MS_RT_LIB=/tmp/decimal-base/target/ms-native/libms_native.a "$ms_compiler" build "$evidence/main.ms" --build-type Release -o /tmp/decimal-before
MS_BACKEND=cranelift MS_RT_LIB=/tmp/decimal-candidate/target/ms-native/libms_native.a "$ms_compiler" build "$evidence/main.ms" --build-type Release -o /tmp/decimal-after
MS_BACKEND=cranelift MS_RT_LIB=/tmp/decimal-base/target/ms-native/libms_native.a "$ms_compiler" build "$control_source" --build-type Release -o /tmp/control-before
MS_BACKEND=cranelift MS_RT_LIB=/tmp/decimal-candidate/target/ms-native/libms_native.a "$ms_compiler" build "$control_source" --build-type Release -o /tmp/control-after
```

Use a writable `XDG_CACHE_HOME` when the home directory is read-only. After builds
finish, with no concurrent CPU-heavy work and an available CPU selected:

```sh
taskset -c 0 python3 bench/perf/decimal-truncate/repeat.py /tmp/decimal-before /tmp/decimal-after /tmp/decimal-rust-build/release/decimal-truncate-baseline > /tmp/paired.jsonl
taskset -c 0 python3 bench/perf/decimal-conversions/repeat.py /tmp/control-before /tmp/control-after 8 > /tmp/conversion-controls.jsonl
taskset -c 0 python3 bench/perf/decimal-truncate/long_controls.py /tmp/control-before /tmp/control-after > /tmp/long-controls.jsonl
```

The fixed main repetition count must be a positive multiple of eight. The
long-control script reuses the existing conversion suite's output/oracle checker.
This experiment does not establish the rest of the numeric lane as clean.
