# Decimal primitive conversions and negation

The runtime stored every Decimal coefficient in 128 bits but constructed temporary
`BigInt`s to convert an `Int`/`UInt64` or negate a Decimal. Integer normalization
also performed arbitrary-precision quotient/remainder operations. All integer
inputs fit in the existing representation, and a valid Decimal coefficient has
at most 34 digits, so these operations can use fixed-width arithmetic directly.
No representation, public signature, rounding rule, or error behavior changes.

## 2026-10-29 measurements

The baseline runtime is **`4ceb772afe59c6a73305b94c2ab395e60b0611ca`**. The changed
runtime differs only in `crates/ms-std-decimal/src/lib.rs`. The same compiler and
workload built both executables, selecting each archive with `MS_RT_LIB`.
Both `.ms-build.json` files report `backend: cranelift`, `build_type: Release`.
Release uses MIR `Level::Speed` and Cranelift `opt_level: speed`; the native runtime
was built by `cargo xtask runtime` with Cargo release optimization (level 3) and
debug information disabled. These are **not LLVM measurements**. No backend or
CPU overrides were set during the recorded run.

Linux x86_64, kernel 6.18.55, Intel Xeon Platinum 8573C under KVM; five visible
CPUs, four-CPU cgroup quota, 16 GiB memory limit. Rust 1.99.1
(`58cf8f9c3 2026-10-13`), num-bigint 0.5.1. No local build or other benchmark ran
concurrently with the measurements. Shared-VM noise remains visible in the ranges.

Seven paired samples follow a separate warmup for every case, alternating binary
order. The table gives internal **ns/operation, median [minimum–maximum]**;
[raw samples](results-2026-10-29.jsonl) also retain process wall time and checksums.
Compilation, input parsing, value setup, output, and process startup are outside
the internal timer. Loop arithmetic and assignment remain inside it. `stream`
consumes every conversion by truncating it back to Int and accumulating a checked
sum; its times include truncation, which this patch does not change.

| Operation | Count | Seed | Before ns/op | After ns/op |
| --- | ---: | ---: | ---: | ---: |
| Int conversion | 1 | 0 | 127 [107–165] | 155 [112–181] |
| Int conversion | 10,000 | 0 | 50.19 [41.37–150.89] | 3.25 [3.23–4.64] |
| Int conversion | 1,000,000 | 0 | 56.68 [54.28–70.15] | 4.20 [3.50–7.14] |
| Int conversion | 1,000,000 | -1,000,000,000 | 55.71 [46.27–63.04] | 3.90 [3.37–5.02] |
| Int conversion | 1,000,000 | 9,223,372,036,800,000,000 | 57.11 [51.97–60.09] | 3.96 [3.77–4.22] |
| UInt64 conversion | 1,000,000 | 0 (UInt64 maximum) | 54.28 [50.21–62.32] | 2.47 [2.28–3.35] |
| UInt64 conversion | 1,000,001 | 1,000,000,000,000,000,000 | 55.45 [51.37–81.10] | 2.57 [2.18–3.32] |
| Conversion + truncation stream | 1,000,000 | 0 | 96.22 [89.87–101.69] | 40.16 [38.87–40.96] |
| Negation | 1 | 0 | 232 [182–245] | 204 [144–220] |
| Negation | 10,000 | 12,345 | 30.42 [27.40–64.02] | 2.04 [2.03–10.32] |
| Negation | 1,000,000 | 12,345 | 39.04 [31.19–48.99] | 2.63 [2.19–3.15] |
| Negation | 1,000,001 | -9,223,372,036,854,775,808 | 34.07 [29.90–58.81] | 2.70 [2.13–3.68] |

Single-operation timings include timer overhead and do not resolve a useful speed
difference. Conversion inputs vary over 10,000 consecutive integers, including
zeros and trailing-zero normalization. The unsigned power-of-ten case covers
normalization near a large representable integer. Odd negation counts check that
the sign really changes. Each producer must exit successfully; the harness rejects
stderr, malformed/missing rows, changed identities, and results that disagree with
an independent Python integer/Decimal oracle. Every recorded sample passed.
The loops call external native routines, with increasing count and the consumed
stream providing additional evidence that work remained observable.

Artifact SHA-256 identities:

```text
compiler 189e13f1fe20407e4e679fbe64ad2297290500e9a4e3625bc86b78d3289f6ae8
before runtime b39aa926f2d7b1d0400cf3faddcece7562c5ff91edf9a7885372cfbcc056cf22
after runtime 788c490c27b04ddb4e169fa2d5802cce13a17b3dae42d41bebc8a1525026ac9d
measured main.ms e2cd574f5b8c55e618e9b7c5b5cc215df3e1ca3e287bf2055573b30cd70e5b70
repeat.py d620cf7326db14b72450c8f8b945c45dae91e7a7d5ab75bd748579da702b2534
```

The measured source is retained in commit `0748a28e1`; the checked-in `main.ms`
subsequently received formatter-only layout changes. Executable hashes are in the
first two raw rows. Archive sizes decreased from 47,033,256 to 47,029,740 bytes.
No heap-allocation counter or cross-platform performance measurements were taken;
removal of the temporary BigInts follows directly from the changed code.

## Reproduce

From a checkout containing this change, with the repository's pinned Rust toolchain,
C compiler, and normal build prerequisites:

```sh
git worktree add --detach /tmp/decimal-before 4ceb772afe59c6a73305b94c2ab395e60b0611ca
(cd /tmp/decimal-before && cargo xtask runtime)
cargo xtask runtime
cargo build --release --locked -p ms-cli
MS_BACKEND=cranelift MS_RT_LIB=/tmp/decimal-before/target/ms-native/libms_native.a \
  target/release/ms build bench/perf/decimal-conversions/main.ms --build-type Release -o /tmp/decimal-before-program
MS_BACKEND=cranelift MS_RT_LIB="$PWD/target/ms-native/libms_native.a" \
  target/release/ms build bench/perf/decimal-conversions/main.ms --build-type Release -o /tmp/decimal-after-program
python3 bench/perf/decimal-conversions/repeat.py /tmp/decimal-before-program /tmp/decimal-after-program 7
```

The explicit Cranelift selector reproduces the backend reported by the recorded
artifacts; ordinary Release builds may select LLVM when its tools are available.
Run measurements without concurrent builds. This is a profiling guide, not a CI
timing gate or a claim about every numeric workload.
