# Direct Result construction and try propagation

All measurements use the unchanged program sources and pinned Go 1.25.1 on
linux/amd64. `environment.json` records source/binary hashes and ELF text sizes.

- `total-programs-*`: aa3efa72 versus the retained implementation, with shared
  handwritten Go samples. These regenerate the current main results table.
- `retained-programs-*`: bf8aa92e versus the retained implementation, isolating
  direct Result literals and exactly matching failure returns. Thirty trials
  cycle all six Go/before/after orders. Counts and checksums are validated by
  `perf-bench/programs/table.py`.
- `retained-stdlib-*`: thirty alternating executions per revision of all 66
  cases, before/after the local lowering change, with unchanged Go settings.
  The earlier compiler was built using an overlay of bf8aa92e's two lowerer
  files; the runtime and benchmark sources are identical. Every execution
  succeeds and has the same 66 operation names/counts.
- `rejected-runtime-programs-*`: the same bf8aa92e control against direct
  Result lowering plus runtime-only `-l=4`. This is an experiment, not the
  retained implementation.
- `rejected-runtime-stdlib-*`: ten alternating executions per revision,
  isolating the proposed flag after direct Result lowering. Interpolation's
  median rises from 82 to 96.5 ns (uncorrected paired 95% interval 1.07–1.37).
  Several other regression candidates have wide intervals containing 1.
- `rejected-runtime-build-cost.json`: flag-only build-cost control after
  direct Result lowering. Six alternating single-package compiler invocations
  bypass the Go package cache with warm dependencies/filesystem; eight edited
  application builds exclude a warmup pair. Runtime compile median rises
  1.543 -> 1.642 seconds; edited build median is 0.304 -> 0.307 seconds.
  Native program ELF text grows by 2,464 bytes, about 0.13%.

`statistics.json` contains medians and paired percentile bootstrap intervals
(5,000 resamples). Intervals are exploratory and not corrected for the many
comparisons. Integer-quantized short stdlib cases and allocation-heavy cases
are noisy; a median difference alone does not establish a regression.
The retained stdlib comparison has no established regression larger than 5%;
string upper is 2.4% slower with an interval just above 1 among 66 comparisons.

The retained native program try workload improves from 3.572 to 2.838 ns/op,
with after/before interval 0.763–0.827. This does not establish Go parity: its
Go control is 0.564 ns/op. `try` itself is one evaluation, an error discriminator
test and early return; the timed workload also includes checked arithmetic,
result inspection and cancellation polling. The runtime-wide inlining flag
was rejected after the broader measurements and skeptical review.
