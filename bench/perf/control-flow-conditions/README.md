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

## Integration with the other correctness fixes

Main advanced to `1220188933fd2f3dc0fcae9ed7364b5fd1391cdf`, including the
optional literal-context and match diagnostic fixes. Independent merge review
confirmed both are preserved; the production diff still consists only of our two
statement joins. Rebuilt that main and candidate
`65f915137c250eb13099aa10c476a03e9ace49b5` with the same command and repeated
the controls after compilation and other local test workloads completed.

| Case | Latest base, 60 pairs | Latest same binary, 40 pairs |
| --- | ---: | ---: |
| Hello example | 1.0062 | 1.0031 |
| Ordinary, 1 function | 0.9993 | 0.9898 |
| Affected, 1 function | 0.9984 | 1.0028 |
| Ordinary, 64 functions | 1.0041 | 0.9971 |
| Affected, 64 functions | 0.9952 | 1.0136 |

All latest paired medians lie between -0.48% and +0.63%; the previous ordinary-64
3.7% loss again does not repeat. Same-binary median variation extends from -1.02%
to +1.36%. These are still whole-process observations, not proof of zero cost.
[Latest paired samples](latest-paired.json) and
[latest same-binary samples](latest-same-binary.json) include all raw timings,
exact source and binary/output hashes. No earlier runs were removed.

## CPU-time follow-up

Review of `latest-paired.json` found an unfavorable ordinary-64 **mean** change
of +3.65%, despite its +0.41% paired median: fixed's longest sample was 164 ms,
baseline's 105 ms. This tail difference was not discarded or attributed to
scheduling without evidence. The Linux runner now records child user+system CPU
time (`getrusage(RUSAGE_CHILDREN)`) alongside wall time. Binaries and source are
unchanged from the latest-base comparison. The runner uses Unix `resource`; the
reported experiment is Linux-specific.

An 80-pair follow-up and 40 identical-binary pairs gave these paired medians:

| Case | Wall ratio | CPU ratio | Same-binary CPU ratio |
| --- | ---: | ---: | ---: |
| Hello example | 0.9991 | 0.9985 | 1.0113 |
| Ordinary, 1 function | 1.0001 | 1.0004 | 1.0097 |
| Affected, 1 function | 1.0103 | 1.0097 | 1.0098 |
| Ordinary, 64 functions | 0.9910 | 0.9918 | 0.9920 |
| Affected, 64 functions | 0.9990 | 0.9984 | 0.9956 |

Ordinary-64 CPU mean is -3.32%, substantially influenced by a 199 ms baseline
outlier; this does not establish a speedup. Its fixed p95 is slightly higher
(83.1 versus 80.8 ms). Affected-1 CPU mean is +0.83% and p95 58.8 versus 55.9 ms;
the identical-binary control shows +1.74% mean and a larger p95 increase. Wall
and CPU closely track in these new samples, so scheduling alone is not an
established explanation for the earlier wall-only observations.

Independent review found no reproducible performance regression attributable to
the change across the paired and identical-binary controls. Small effects and
tail differences remain unresolved; zero overhead and unchanged tail latency
are not claimed. Raw evidence: [CPU paired](latest-cpu-paired.json),
[CPU same binary](latest-cpu-same-binary.json). Every earlier report remains.
