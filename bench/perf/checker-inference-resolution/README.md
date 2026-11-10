# Checker argument-inference benchmark

Measure complete production `ms check --json` processes for generic argument
inference, including process startup. The workload generator includes nested
generic patterns, explicit-specialization controls, ordinary small callables,
large repeated-parameter callables, Optional retry/widening and rejected inputs.
The large cases are stress workloads; they do not establish application-wide
compiler gains.

Build the base and candidate with the repository-pinned Rust toolchain and
identical `make build` production settings. Preserve both `target/release/ms`
executables before switching source revisions. Use the same machine and avoid
concurrent builds or tests during timing. The measurement harness uses Linux
CPU affinity and resource counters.

Keep generated inputs, raw observations, logs, dated reports and rejected
experiments under the ignored `.artifacts/` directory. Do not commit them.
Record revisions, build settings and machine details beside the local results;
the harness records binary/input hashes, commands, outputs, exits and timings.

```sh
mkdir -p .artifacts/checker-inference-resolution/results
python3 bench/perf/checker-inference-resolution/lazy-contribute/generate.py .artifacts/checker-inference-resolution/inputs
python3 bench/perf/checker-inference-resolution/lazy-contribute/measure.py --binary base=.artifacts/checker-inference-resolution/base/ms --binary candidate=.artifacts/checker-inference-resolution/candidate/ms --inputs .artifacts/checker-inference-resolution/inputs --output .artifacts/checker-inference-resolution/results/paired.json --samples 31
python3 bench/perf/checker-inference-resolution/summarize.py .artifacts/checker-inference-resolution/results
```

The runner warms each case, shuffles case order with a fixed seed, alternates
binary order and checks every stdout, stderr and exit status exactly. Rejected
inputs use the base diagnostic as an oracle; inspect that oracle to confirm the
intended failure. Result files cannot be overwritten. Supply the same base
binary under both labels for an identical-binary comparison.

For a fixed interleaved comparison of Optional retry, an explicit small callable,
arity rejection and the largest inferred callable, run both identical-binary
(A/A) and base/candidate (A/B) pairs within every round:

```sh
python3 bench/perf/checker-inference-resolution/lazy-contribute/interleaved.py --base .artifacts/checker-inference-resolution/base/ms --candidate .artifacts/checker-inference-resolution/candidate/ms --inputs .artifacts/checker-inference-resolution/inputs --output .artifacts/checker-inference-resolution/results/interleaved.json --rounds 61
python3 bench/perf/checker-inference-resolution/lazy-contribute/analyze-interleaved.py .artifacts/checker-inference-resolution/results/interleaved.json
```

Choose sample counts and confirmation controls before viewing their results.
Preserve unfavorable observations and all earlier runs locally. Report paired
ratios, common-case controls and uncertainty alongside a targeted improvement.
The analyzer's intervals assume independent rounds; shared-machine temporal
dependence can weaken coverage. Do not subtract A/A noise from the claimed gain,
interpret an inconclusive interval as equivalence, or keep rerunning until a
control becomes favorable.
