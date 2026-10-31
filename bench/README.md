# Benchmarks and measurement evidence

Each directory has its own run script and committed results naming the revision and machine. Cite these pages for speed or agent claims; rerun and add a dated section instead of editing old numbers.

| Directory | Contents |
| --- | --- |
| [`perf/`](perf/README.md) | Compiler and runtime speed against Go and Rust, standard-library baselines, and per-change trial records (dated `results-*` folders and rejected-trial write-ups). |
| [`agent/`](agent/README.md) | How well agents write programs in different languages. Never shares results with `perf/`. Checked by `make` (`bench/agent/tests`). |
| [`compile-time/`](compile-time/) | Generated-project compile-time measurements for the incremental-builds proposal (`gen.py`, `report.md`). |
| [`language/`](language/) | Small language-level benchmark programs (calls, lists, numeric, life). |
| [`lists/`](lists/) | List storage investigation: programs, pair/memory scripts, results. |
| [`lowering/`](lowering/) | Lowering benchmark programs. |

`language/`, `lists/` and `lowering/` `.ms` files are the origins of the fixtures in `tests/conformance/fixtures/bench/`; keep the paths stable. The `*.go.txt` files are Go-era harnesses kept as evidence only; the Go implementation is removed.
