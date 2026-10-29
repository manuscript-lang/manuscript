# Limited scalar splitting

`String.split("", max_parts: limit)` previously counted every scalar before
producing a small prefix. A decoded scalar consumes at most four bytes, so a
byte length `B` guarantees at least `ceil(B / 4)` decoded scalars. When
`limit <= B / 4`, the exact output count is therefore `limit`; otherwise the
existing count supplies `min(count, limit)`. This holds for the decoder's
invalid-byte fallback too. The copying loop uses this exact allocated count.
Output order, error behavior, and allocation capacity stay unchanged.

## Reproduce

Preserve the baseline runtime archive and `ms_rt_hot.ll`, then build baseline
and candidate executables from the same source using the same compiler and
identical pure-runtime helpers:

```sh
MS_RT_LIB=/tmp/before/libms_native.a ms build \
    bench/perf/string-split-limits/main.ms --build-type Release -o /tmp/before-split
MS_RT_LIB=/tmp/after/libms_native.a ms build \
    bench/perf/string-split-limits/main.ms --build-type Release -o /tmp/after-split
taskset -c 0 python3 bench/perf/string-lines/compare.py \
    /tmp/before-split /tmp/after-split /tmp/split-samples.csv --pairs 7 \
    --identity-file bench/perf/string-split-limits/identities.json
```

Build each archive with `cargo xtask runtime` at its source revision. Release
can fall back to Cranelift: verify the actual LLVM invocations before labeling
results. Input creation, checked warm-up, process startup, compilation and
output are outside timing. List allocation, traversal and release are included.
There are no timing assertions. The runner checks producer exit status and
the full declared inventory of sizes, iterations and checksums on every trial.

The 63 cases combine ASCII, `é日😀`, and four-byte scalars; approximately
64 B, 4 KiB and 1 MiB inputs; and omitted, zero, small, half-length and
full-length limits. In CSV names, requested `-1` means omitted, `-2` means an
explicit half-length cap, and `-3` means an explicit full-length cap. These
negative identifiers are benchmark labels; negative limits are not passed to
the public operation. Mixed prefixes use their actual 2/3/4-byte lengths in
the checksum, not their average width.

## Recorded Linux comparison, 2026-10-29

Intel Xeon Platinum 8573C VM, five exposed CPUs, Linux 6.18.55, Rust 1.99.1,
static musl runtime with frame pointers, LLVM 23.1.1 Release O3. The runner and
children used CPU 0, without concurrent builds/tests. Both executable builds
used the same compiler and identical `ms_rt_hot.ll`; `builds.json` records
source/patch and binary hashes. Each executable had an unrecorded process
warm-up and each case had a checked untimed warm-up.

`samples.csv` retains all 882 rows (63 cases, two variants, seven alternating
pairs). `summary.csv` gives every median and min/max range in ns per split.
Representative prefix-one results:

| Input | Before median | After median | After range |
| --- | ---: | ---: | ---: |
| ASCII, 64 B | 16.3 ns | 14.0 ns | 11.6–26.1 ns |
| ASCII, 4 KiB | 58.8 ns | 11.4 ns | 11.3–29.1 ns |
| ASCII, 1 MiB | 22.5 µs | 11.6 ns | 10.7–27.3 ns |
| Mixed UTF-8, 4095 B | 6.6 µs | 14.9 ns | 14.7–16.1 ns |
| Mixed UTF-8, 1048572 B | 1.74 ms | 15.7 ns | 14.3–25.5 ns |
| Four-byte scalars, 1 MiB | 1.40 ms | 16.8 ns | 15.8–63.7 ns |

These large prefix gains come from removing the full-input count. Small
optimized cases use only hundreds or thousands of iterations, so their
nanosecond values and enormous ratios should not be treated as precise
cross-machine claims.

Common controls are not uniformly faster. The combined run reports mixed
4095-byte unlimited splitting about 16.6% slower and mixed 1 MiB unlimited
splitting about 6.6% slower. In the separate `full-controls.ms` run (six cases,
nine alternating pairs; 108 rows), those medians are about 4.4% and 1.2%
slower. The 63-byte mixed unlimited control is about 9.1% slower in isolation,
while its combined-run median is essentially unchanged. Both sets of
observations are retained; the focused run does not invalidate the combined
one. Zero-limit differences are also recorded, including small absolute
increases. This is a workload-specific improvement, not a universal speedup.

Run focused controls with `full-controls.ms`,
`full-control-identities.json`, and `--pairs 9`. Their full distributions are
in `full-control-samples.csv` and `full-control-summary.csv`.

Exploratory samples and source snapshots remain under `exploratory/` and in
the `initial-`, `helper-`, and `bounded-` sample files. They include rejected
common-case regressions and earlier weaker short controls. They are not
pooled with the final distributions. Other platforms were not measured.
