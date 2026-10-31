# Shortest Float formatting without heap scratch buffers

`float_to_string` previously formatted a positive finite magnitude into a temporary
`Vec`, then copied its mantissa digits into a second temporary `Vec`, before
rendering the result. Both scratch values fit in bounded storage. The changed
runtime writes the same Rust scientific formatter into 32 bytes of character
storage plus length metadata, removes its decimal point in place, and keeps the
existing notation/sign renderer and final output vector.

The longest positive finite binary64 scientific form needs at most 17 digits,
one decimal point, `e`, an exponent sign and three exponent digits: 23 bytes.
Binary32 is smaller. No rounding algorithm, public signature, notation threshold,
or explicit-precision formatter changes. This is separate from the already-fixed
duplicate conversion in `Float.to_precision` (#1806/#1834).

## Pinned release measurements, 2026-10-29

Baseline: **`4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`**. Baseline and candidate
native archives differ only in `crates/ms-rt/src/num.rs`; the same compiler and
workload built both executables using `MS_RT_LIB`.

Every build explicitly selected **`MS_BACKEND=cranelift`** and
`--build-type Release`: MIR speed optimization and Cranelift `speed`. The native
Rust runtime was built separately by `cargo xtask runtime`, with Cargo release
optimization (level 3), debug information disabled, and the Linux musl target.
The selector establishes the backend independently of the build sidecar label.
There is no LLVM-generated-program or cross-platform performance claim.

Environment: Linux x86_64 6.18.55, Intel Xeon Platinum 8573C KVM, five visible CPUs,
four-CPU cgroup quota, 16 GiB memory limit; Rust 1.99.1
(`58cf8f9c3 2026-10-13`). Controlled runs pinned the launcher and children to CPU 0.
No local build or test ran during measurements. OS page caches were not flushed.
The shared host still produced substantial variation and outliers.

Compilation, argument parsing, setup, output, and process startup are outside the
internal monotonic timer. Timed work includes numeric input variation, formatting,
assignment/drop of the previous string, and reading every string's byte length.
Every producer receives an independent expected length checksum and final text,
and exits unsuccessfully on a mismatch. The Python runner also rejects failed
producers, stderr, malformed identities, wrong checksums/final text, missing
samples and invalid timing bounds. Eighths are checked using integer arithmetic;
the exponent/special cases use explicit known strings. This checks every output's
length and the final output's exact text; it does not independently compare every
intermediate string's contents.

## Results and controls

The CPU-pinned comparison has eight balanced before/after pairs per case following
a separate warmup. Values below are internal **ns/operation, median [min–max]** for
one million operations. All raw samples are retained.

| Case | Before | After |
| --- | ---: | ---: |
| Varying exact eighths | 303.07 [264.61–353.04] | 255.06 [197.16–315.38] |
| Integral control | 70.39 [50.11–88.11] | 57.93 [48.54–79.88] |
| Signed small scientific values | 296.25 [228.84–491.82] | 230.21 [193.97–453.36] |
| Alternating maximum/subnormal | 366.12 [340.34–484.44] | 243.28 [235.45–287.20] |
| NaN/infinity control | 39.79 [36.44–54.41] | 44.26 [38.29–59.99] |
| Interpolated numeric report | 289.57 [273.92–347.53] | 240.31 [222.37–268.79] |

Wide formatting and the report were faster in all eight pairs. Their paired
median after/before ratios were 0.657 and 0.821. Integral/nonfinite values bypass
the changed scientific path, but their observed timings cannot be assumed constant.

The first unaffinitized run was mixed, so it was not sufficient to retain the
change. A CPU-pinned identical-binary A/A run then showed apparent integral and
scientific gains even though both labels used the exact same executable. It also
showed large small-case variation. The pinned candidate's initial nonfinite
slowdown therefore required a stronger control, rather than being dismissed from
overlapping ranges.

Before that final control, the protocol was fixed: 12 balanced paired repeats,
10 million iterations for nonfinite/integral controls, one million for a wide
formatting anchor, interleaved identical-baseline A/A pairs, and rotating case
order. The result was:

| Long control | Before median ns/op | After median ns/op | Candidate paired ratio | A/A paired ratio | Candidate faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| NaN/infinity | 41.02 | 41.46 | 1.003 | 0.990 | 6/12 |
| Integral | 63.32 | 61.14 | 1.030 | 0.910 | 5/12 |
| Maximum/subnormal anchor | 372.15 | 247.40 | 0.637 | 1.019 | 12/12 |

The earlier nonfinite slowdown did not persist in this predeclared session.
Integral and small-case costs remain uncertain; neither an integral gain nor an
all-path no-regression claim is justified. Whole-producer CPU time corroborates
the wide result (paired ratio 0.638); those CPU measurements include startup and
setup, unlike the internal wall timer. CPU time does not remove all host noise.
Actual long-session outliers include 440.42 ns/op for an identical-baseline
integral run and 1406.95 ns/op for an identical-baseline wide run; none were removed.

Raw evidence:

- [Initial unaffinitized exploration](results/initial-unpinned.jsonl), 200k batches;
  the earlier harness revision was not retained, so this is exploratory evidence,
  excluded from headline claims.
- [Pinned identical-binary A/A](results/aa-pinned.jsonl), one-million batches.
- [Pinned candidate comparison](results/candidate-pinned.jsonl), one-million
  batches plus 1/1000-operation controls.
- [Predeclared interleaved long controls](results/long-controls.jsonl), including
  all warmups and all measured observations.

Across the four files all 912 producer invocations, including warmups, passed the
output checks. Independent Sol 6.1 review recomputed identities, ordering,
checksums, final text, summaries and the long-control ratios. Native unit tests
make 69,632 exact old/new formatter comparisons across every IEEE exponent,
boundary mantissas, signs, and varied bit patterns. The called Float64 source
fixture covers notation boundaries, signed zero, NaN and infinities in Debug and
Release. No allocation counter, RSS, or instruction-count measurement is claimed;
the removal of two temporary vector objects follows from the source change.

## Reproduce

Use the repository's pinned Rust toolchain and normal native build prerequisites.
The measurement harness uses Linux CPU affinity and POSIX child CPU accounting.
Choose an available CPU if CPU 0 is outside the local allowed affinity set.

```sh
git worktree add --detach /tmp/float-before 4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192
(cd /tmp/float-before && cargo xtask runtime)
cargo xtask runtime
cargo build --release --locked -p ms-cli
MS_BACKEND=cranelift MS_RT_LIB=/tmp/float-before/target/ms-native/libms_native.a \
  target/release/ms build bench/perf/float-formatting/main.ms --build-type Release -o /tmp/float-before-program
MS_BACKEND=cranelift MS_RT_LIB="$PWD/target/ms-native/libms_native.a" \
  target/release/ms build bench/perf/float-formatting/main.ms --build-type Release -o /tmp/float-after-program
python3 bench/perf/float-formatting/repeat.py /tmp/float-before-program /tmp/float-before-program 8 --cpu 0 --batch-count 1000000 > /tmp/float-aa.jsonl
python3 bench/perf/float-formatting/repeat.py /tmp/float-before-program /tmp/float-after-program 8 --cpu 0 --batch-count 1000000 > /tmp/float-candidate.jsonl
PYTHONDONTWRITEBYTECODE=1 python3 bench/perf/float-formatting/controls.py /tmp/float-before-program /tmp/float-after-program --cpu 0 > /tmp/float-controls.jsonl
```

Recorded SHA-256 identities (executable hashes are also in each raw file):

```text
compiler b62ad4c4a5dbdff93a8b491582460445cd4c1b17f44b42f3b14490dd8846dd69
before archive 3e569fc654fab3efd7983b6e3d136eff65961456401b388d16619e231af6b16f
after archive e676384c00edc050cbb7206198ccf4b4381eb8000417475801b3bcb80f804ad4
main.ms 39b7189e0373447c5b7b7d8dbdcb04c4f8027f8aa334b2c7ab43c162e20c95a7
repeat.py c851ede4ebe6a25af79cf49e934b5f450bfb8a22c5c9fe87cad2adcc0e494769
controls.py ee6253fdbf17bd8c31d46631d81856e39e0ea93bf104a8c37ead241a9fe5e721
```

## Excluded observation

A newly authored source-level Float32 control at this baseline expected `0.1`
but observed `0.10000000149011612` from `let value: Float32 = 0.1` followed by
`value.to_string()`, with both the baseline and candidate archives. The underlying
width/dispatch behavior was not investigated under this lane's compiler exclusion.
Public Float32 performance cases and that new assertion are excluded from this
change; no existing test was disabled. The internal binary32 formatter remains
covered by exact differential tests. No public Float32 width/performance fix is
claimed. Native Windows and macOS performance were not measured.
