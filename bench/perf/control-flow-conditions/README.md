# Nonreturning condition reachability — 2026-11-10

Correctness patch: ignore unreachable branch breaks after a condition cannot
return, while retaining breaks originating inside the condition. This is not a
speed optimization. The return-completeness regression is established separately
by `crates/ms-check/tests/control_flow.rs`.

Base: `ae87acedab5641ffac4179b17e3e0dc442fcca0e`.
Measured implementation: `6790c2d5a7ef433e2a9ee0aca01faf1cf1a739f6`.
Later evidence-only commits do not change the measured checker code.

Both `ms-check-dev` binaries were built with repository-pinned Rust 1.99.1,
`cargo build --release --locked -p ms-check --bin ms-check-dev`, on this Linux
x86_64 cloud machine. Each JSON report records the machine, CPU affinity, exact
binary/source/output SHA-256 values and every raw elapsed-nanosecond sample.
Builds and other local test workloads completed before timing.

The runner measures fresh frontend processes, including startup, parsing and
standard-library loading. It checks the real hello example, a small loop reducer
and 64 independent copies, and 1/64 affected helpers. The affected controls retain
a trailing return so both revisions accept identical source and emit identical
empty diagnostic JSON. The regression fixture separately tests corrected
acceptance without that workaround. Nothing executes the source program here.

Every case has two warmup pairs. Measured pairs alternate base/fixed and
fixed/base order on one pinned CPU. Every invocation must exit successfully,
produce no stderr, and produce exactly the same stdout. No samples were removed.
The labels `base` and `fixed` in the same-binary report name the *same* executable.

Median of paired fixed/base elapsed-time ratios:

| Case | Initial 20 pairs | Same binary, 40 pairs | Confirmation, 60 pairs |
| --- | ---: | ---: | ---: |
| Hello example | 1.0044 | 0.9800 | 1.0081 |
| Ordinary, 1 function | 1.0178 | 1.0020 | 1.0071 |
| Affected, 1 function | 0.9757 | 1.0043 | 1.0008 |
| Ordinary, 64 functions | 1.0367 | 1.0040 | 1.0048 |
| Affected, 64 functions | 0.9780 | 1.0059 | 1.0026 |

The initial ordinary-64 result was unfavorable: 15/20 pairs were slower and its
3.7% median loss persisted across both execution orders. It triggered the
same-binary and larger confirmation runs. The confirmation did not reproduce
that magnitude; its 0.48% median change is close to the 0.40% same-binary result.
All confirmation medians are within 0.82%. These process-level measurements do
not prove zero checker overhead or an application speedup, and cannot exclude
small changes obscured by startup and shared-machine variation. Retain the first
run rather than replacing it with the favorable confirmation.

Raw evidence: [initial](paired.json), [same binary](same-binary.json),
[confirmation](paired-confirmation.json). Reproduce after building both revisions:

```sh
python3 bench/perf/control-flow-conditions/run.py /path/to/base/ms-check-dev /path/to/fixed/ms-check-dev --pairs 20 --output paired.json
python3 bench/perf/control-flow-conditions/run.py /path/to/base/ms-check-dev /path/to/base/ms-check-dev --pairs 40 --output same-binary.json
python3 bench/perf/control-flow-conditions/run.py /path/to/base/ms-check-dev /path/to/fixed/ms-check-dev --pairs 60 --output paired-confirmation.json
```
