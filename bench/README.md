# Benchmarks and measurement evidence

Performance is one suite: [`perf/groups.txt`](perf/groups.txt) indexes every group and `make perf-list` / `make perf GROUP=<name>` runs them (see [`perf/README.md`](perf/README.md)). Each group has committed results naming the revision and machine. Cite these pages for speed or agent claims; rerun and add a dated section instead of editing old numbers.

| Directory | Contents |
| --- | --- |
| [`perf/`](perf/README.md) | The performance suite: compiler and runtime speed against Go and Rust, standard-library baselines, and per-change trial records (dated `results-*` folders and rejected-trial write-ups). Finished trial folders that nothing cites are deleted; git history has them. |
| [`agent/`](agent/README.md) | How well agents write programs in different languages. Never shares results with `perf/`. Checked by `make agent-bench-check` (`bench/agent/core_test.ms`). |
| [`compile-time/`](compile-time/) | Group `compile-time` of the suite: generated-project compile-time measurements for the incremental-builds proposal (`gen.py`, `report.md`). |
| [`language/`](language/) | Group `language` of the suite: small language-level benchmark programs (calls, lists, numeric, life). |
| [`lists/`](lists/) | Group `lists` of the suite: list storage benchmark programs. |
| [`lowering/`](lowering/) | Lowering benchmark programs, run by the `language` group's tooling and kept for the conformance fixtures. |

`language/`, `lists/` and `lowering/` `.ms` files are the origins of the fixtures in `tests/conformance/fixtures/bench/`; keep the paths stable.
