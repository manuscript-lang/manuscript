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
Both final executables were built with **`MS_BACKEND=cranelift`** and
`--build-type Release`. The explicit selector disables the optional LLVM path;
this is Cranelift with MIR `Level::Speed` and Cranelift `opt_level: speed`.
The sidecars also report `backend: cranelift`, `build_type: Release`, but the
explicit selector, rather than that label alone, establishes the backend.
The native runtime was built by `cargo xtask runtime` with Cargo release
optimization (level 3) and debug information disabled. `MS_CPU_LEVEL` was unset.
These final results do not measure LLVM or another platform.

Linux x86_64, kernel 6.18.55, Intel Xeon Platinum 8573C under KVM; five visible
CPUs, four-CPU cgroup quota, 16 GiB memory limit. Rust 1.99.1
(`58cf8f9c3 2026-10-13`), num-bigint 0.5.1. No local build or other benchmark ran
concurrently with the measurements. Shared-VM noise remains visible in the ranges.

Eight paired samples follow a separate warmup for every case, alternating binary
order. The table gives internal **ns/operation, median [minimum–maximum]**;
[raw samples](results-2026-10-29-cranelift.jsonl) also retain process wall time and checksums.
Compilation, input parsing, value setup, output, and process startup are outside
the internal timer. Loop arithmetic and assignment remain inside it. `stream`
consumes every conversion by truncating it back to Int and accumulating a checked
sum; its times include truncation, which this patch does not change.
`add-round` follows the existing `decimal.add_round` standard-library benchmark:
convert an integer, add `1.12345d`, round to two places, truncate and accumulate.
It includes both a 20,000-operation common case and a longer scaling control.

| Operation | Count | Seed | Before ns/op | After ns/op |
| --- | ---: | ---: | ---: | ---: |
| Int conversion | 1 | 0 | 248 [188–322] | 204 [188–276] |
| Int conversion | 10,000 | 0 | 46.61 [43.35–123.85] | 3.72 [3.71–15.22] |
| Int conversion | 1,000,000 | 0 | 58.49 [54.10–70.99] | 4.72 [4.27–6.32] |
| Int conversion | 1,000,000 | -1,000,000,000 | 57.02 [51.49–73.54] | 4.65 [4.29–6.04] |
| Int conversion | 1,000,000 | 9,223,372,036,800,000,000 | 60.40 [53.88–78.60] | 4.91 [4.45–8.21] |
| UInt64 conversion | 1,000,000 | 0 (UInt64 maximum) | 55.64 [51.14–64.77] | 3.80 [3.07–7.23] |
| UInt64 conversion | 1,000,001 | 1,000,000,000,000,000,000 | 58.71 [51.34–68.48] | 3.74 [3.03–4.47] |
| Conversion + truncation stream | 1,000,000 | 0 | 99.96 [89.65–122.87] | 42.93 [37.42–51.47] |
| Add + round + truncate | 20,000 | 0 | 728.70 [595.43–1365.36] | 608.92 [518.75–677.26] |
| Add + round + truncate | 200,000 | 0 | 691.68 [664.42–784.77] | 622.57 [565.42–725.50] |
| Negation | 1 | 0 | 367 [319–497] | 326.5 [262–418] |
| Negation | 10,000 | 12,345 | 29.25 [27.09–58.60] | 2.38 [2.37–2.40] |
| Negation | 1,000,000 | 12,345 | 42.04 [35.51–50.12] | 2.93 [2.39–3.27] |
| Negation | 1,000,001 | -9,223,372,036,854,775,808 | 37.66 [34.14–60.76] | 2.90 [2.75–4.04] |

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
measured main.ms dbd95c3f6b03cb4912fdffcd51d4b701372dd3b90b0cc12c1a01e929491514aa
repeat.py 6731dab6ffd68d6a000e531444d481e30cf23985d8ec303c64f66adb6fd706a1
```

Executable hashes are in the first two raw rows. Archive sizes decreased from
47,033,256 to 47,029,740 bytes.
No heap-allocation counter or cross-platform performance measurements were taken;
removal of the temporary BigInts follows directly from the changed code.

An earlier default-Release run is retained separately as
[unverified-backend raw samples](results-2026-10-29-unverified-backend.jsonl).
Its backend is unverified and it is not used for the headline claims above.
That initial source is retained in commit `0748a28e1` (main.ms SHA-256
`e2cd574f5b8c55e618e9b7c5b5cc215df3e1ca3e287bf2055573b30cd70e5b70`,
repeat.py `d620cf7326db14b72450c8f8b945c45dae91e7a7d5ab75bd748579da702b2534`).
The final source also adds the representative add-and-round control.

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
python3 bench/perf/decimal-conversions/repeat.py /tmp/decimal-before-program /tmp/decimal-after-program 8
```

The explicit Cranelift selector fixes the backend independently of default Release
selection or the sidecar label; ordinary Release builds may select LLVM when its tools are available.
Run measurements without concurrent builds. This is a profiling guide, not a CI
timing gate or a claim about every numeric workload.
