# Call candidate resolution benchmark

Run the Manuscript drivers from the repository root on a Linux measurement host
with Bash, `timeout` and `taskset`. Build both compiler revisions with `make build`
using the same pinned Rust toolchain and machine. Stop other builds and tests
before measuring. Store binaries and all generated evidence under `.artifacts/`;
do not commit dated investigation records or raw benchmark output.

`bench/tools/call_candidates.ms` generates source-method chains, equivalent flat
calls and native callback chains, plus checks representative repository programs.
`bench/tools/call_candidates_build.ms` measures uncached Release builds and checks
each resulting native program's exact output. Both alternate binary order; round0
is retained but excluded as warm-up. An optional final argument selects one exact
input filename for isolated controls. The build driver uses the same output path
for both binaries.

Each timed command also records Bash's user/system CPU counters, separately from
wall latency. Wall time includes process startup, waits, I/O and timer processing;
its difference from CPU time is not pure scheduling delay. Counter precision is
one millisecond. The paired-summary tool accepts `forward cpu` or `swap cpu` and
reports a binomial order-statistic interval with at least 95% coverage for the
median ratio, assuming independent pairs. For small CPU margins, also account for
counter quantization: a conservative upper ratio is `(candidate + 2ms) /
(baseline - 2ms)` when the denominator is positive. Preserve both process orders
and report wall and CPU results;
do not infer universal performance parity from an interval on one control.

```sh
ms build bench/tools/call_candidates.ms --build-type Release -o .artifacts/check-calls
ms build bench/tools/call_candidates_build.ms --build-type Release -o .artifacts/build-calls
.artifacts/check-calls BEFORE AFTER .artifacts/calls 15
.artifacts/build-calls BEFORE AFTER .artifacts/calls/inputs .artifacts/call-builds 7
ms run bench/tools/call_candidates_table.ms -- .artifacts/calls/samples.tsv
ms run bench/tools/call_candidates_pairs.ms -- .artifacts/calls/samples.tsv
```

Use a same-binary control and reverse the binary arguments when investigating
small differences. Pass `swap` to the paired-summary tool for reversed labels.
Keep all samples, exact compiler/input hashes and native build metadata. Inspect
both ordinary medians and matched-pair ratios; neither establishes a cause alone.
The phase-summary tool reads `MS_TIMINGS=1` native8 build logs and separates native
phase deltas from the remaining wall time, which is not checker time alone.
The recorded stderr includes the timer's `CALL_CPU` marker; compare compiler
diagnostics separately from that marker. Command records preserve the full Bash
wrapper and its arguments.
