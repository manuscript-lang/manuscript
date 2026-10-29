# String line splitting

This benchmark measures generated-program runtime for `String.lines()`, including
its result allocation and traversal. Input construction, compilation, process
startup, output, and an initial checked warm-up of each case are outside the timed
region. Every result contributes its line count and byte lengths to a checked
checksum. There is no CI timing threshold.

`compare.py` runs seven alternating before/after pairs. It rejects producer
failures, missing or duplicate cases, changed input sizes or iteration counts,
incorrect checksums, and nonpositive timings. It writes all samples before
printing medians and ranges in nanoseconds per `lines()` call.

## Reproduce

Build the compiler and native runtime at the baseline revision, then preserve the
archive and use the same compiler and source for both executables:

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
cp target/ms-native/libms_native.a /tmp/string-lines-before.a
MS_RT_LIB=/tmp/string-lines-before.a target/release/ms build \
    bench/perf/string-lines/main.ms --build-type Release -o /tmp/string-lines-before
```

Apply the runtime patch, rebuild its archive, and build the second executable:

```sh
cargo xtask runtime
MS_RT_LIB="$PWD/target/ms-native/libms_native.a" target/release/ms build \
    bench/perf/string-lines/main.ms --build-type Release -o /tmp/string-lines-after
python3 bench/perf/string-lines/compare.py \
    /tmp/string-lines-before /tmp/string-lines-after /tmp/string-lines-samples.csv
```

The compiler, its embedded pure-runtime helpers, and benchmark source must match
between builds. Copy this directory into the baseline checkout when reproducing
from a revision that predates the harness. Stop other builds and CPU workloads
before timing. Verify the selected backend: Release can fall back to Cranelift
if LLVM tools are unavailable; `--build-type Release` alone does not prove LLVM
was used. Record the host, source revisions, tools, backend, optimization level,
and executable/source/archive hashes with any published results.

The source controls include empty text, adjacent empty lines, tiny and short
unterminated text, LF offsets around 8/16/32-byte search boundaries, increasingly
long LF lines, Unicode with CRLF, and a 1 MiB string without a newline. Output
allocation and copying remain part of this operation's cost.

## 2026-10-29: Linux x86_64

Measured on an Intel Xeon Platinum 8573C VM with five exposed CPUs, Linux
6.18.55, Rust 1.99.1, and LLVM 23.1.1. Both generated programs used Release,
`opt -passes=default<O3>`, `llc -O3`, and the static musl runtime, with frame
pointers retained. Execution traces confirmed LLVM tools ran for both builds.
The runner and children were pinned to CPU 0; no builds or tests ran during
measurement. Nine alternating pairs followed one unrecorded process warm-up
per executable; each case also has its own checked untimed warm-up.

Native baseline: `4c0a1cb820e772f56a0c831a0f2fe37fbc96a9a7`.
Candidate and shared compiler: `293f45361725d81945cc0b71fb5fdee3a1f902b2`,
which includes main through `7e2e62357`. Intervening main changes add Iterable
and repair HTTP rejection handling; the benchmark imports string, time, and
stdio operations. The baseline executable was byte-identical before and after
refreshing the compiler. Full build hashes are in `builds.json`.

`samples.csv` contains every final sample (288 rows). Values below are per
`lines()` call, including result allocation, traversal, and release; brackets
show the minimum and maximum across all nine samples.

| Small control | Before ns, median [min, max] | After ns, median [min, max] |
| --- | ---: | ---: |
| empty | 4.4 [3.8, 6.2] | 5.1 [4.6, 5.6] |
| two one-byte lines | 18.1 [15.6, 21.3] | 18.2 [16.8, 24.6] |
| short unterminated | 17.5 [14.7, 24.1] | 16.2 [14.8, 22.5] |
| four empty lines | 26.3 [24.4, 32.5] | 29.2 [25.8, 34.7] |

| Approximately 1 MiB input | Before µs, median [min, max] | After µs, median [min, max] | Speedup |
| --- | ---: | ---: | ---: |
| LF, 7-byte lines | 1372.1 [1252.3, 1462.8] | 1157.9 [1145.2, 1372.0] | 1.18× |
| LF, 8-byte lines | 1377.0 [1191.1, 1610.4] | 1103.9 [944.9, 1543.4] | 1.25× |
| LF, 15-byte lines | 1071.9 [983.6, 1266.4] | 587.9 [562.1, 839.1] | 1.82× |
| LF, 16-byte lines | 1307.3 [1197.4, 1405.8] | 995.9 [932.8, 1227.3] | 1.31× |
| LF, 31-byte lines | 892.4 [800.0, 1038.7] | 574.5 [538.4, 713.1] | 1.55× |
| LF, 32-byte lines | 978.7 [846.4, 1094.7] | 763.3 [667.1, 897.1] | 1.28× |
| LF, 128-byte lines | 599.1 [492.6, 639.5] | 237.8 [210.8, 289.1] | 2.52× |
| LF, 1024-byte lines | 467.2 [389.4, 2544.8] | 67.9 [62.0, 114.7] | 6.88× |
| LF, 8192-byte lines | 464.1 [409.6, 3588.4] | 58.2 [50.0, 80.0] | 7.98× |
| LF, 65536-byte lines | 430.3 [364.0, 3003.3] | 52.1 [45.5, 69.2] | 8.25× |
| Unicode CRLF | 482.6 [455.2, 899.7] | 71.4 [58.1, 112.3] | 6.76× |
| no newline | 480.6 [419.0, 661.0] | 68.9 [57.5, 97.8] | 6.97× |

The fix scans nearby line endings directly and uses vector byte search after
the first 32 bytes of a long remainder. Large-input gains are clear despite
VM noise. This is not a universal speedup: empty text increases by 0.63 ns
(14.3%, slower in 7/9 pairs), and four empty lines increase by 2.87 ns
(10.9%, slower in 8/9 pairs). Tiny two-line text increases by 0.17 ns (1.0%).
These small absolute costs are retained explicitly. Other platforms and hosts
were not measured.

`initial-samples.csv`, `second-samples.csv`, and `prefix-samples.csv` retain
exploratory versions, including the rejected tiny-input regressions. The first
used 100,000 small-case iterations and 16 large-case iterations; subsequent
runs used the final 1,000,000 and 64 counts. Their runtime patches and build
identities are recorded in `builds.json` and `exploratory/`; they are not merged
into the final distributions above. Reproduce the final recorded sample count
with `compare.py --pairs 9`.
