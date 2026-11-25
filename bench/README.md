# Benchmarks and measurement evidence

Performance is one suite: [`perf/groups.txt`](perf/groups.txt) indexes every group and `make perf-list` / `make perf GROUP=<name>` runs them (see [`perf/README.md`](perf/README.md)). Each group has committed results naming the revision and machine. Cite these pages for speed or agent claims; rerun and add a dated section instead of editing old numbers.

| Directory | Contents |
| --- | --- |
| [`perf/`](perf/README.md) | The performance suite: every compiler, runtime, standard-library, concurrency and compile-time measurement against Go, Rust and checked C, with one runner (`make perf`) and one results page ([`perf/results.md`](perf/results.md)). Finished investigations are deleted and indexed in the wiki; git history has them. |
| [`agent/`](agent/README.md) | How well agents write programs in different languages. Never shares results with `perf/`. Checked by `make agent-bench-check` (`bench/agent/core_test.ms`). |

