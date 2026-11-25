[Wiki](../index.md) › [Benchmarks and performance](index.md)

# There is one perf suite, indexed by `bench/perf/groups.txt`

Decision (Chinmay, 2026-11-25): perf tests were scattered over `bench/`, `bench/perf/` and `tests/`, so they are one suite with one runner (`make perf-list`, `make perf GROUP=<name>`, `bench/perf/tools/perf.ms`) and one index, [`groups.txt`](../../../bench/perf/groups.txt). Each group has a kind, a command and a results page; `make perf-check` (part of `make bench-check`) fails on a group without a results page or README row, and on a path under `bench/perf/` that is not a group's.

A new benchmark is a row in `groups.txt` and in the `bench/perf/README.md` table. Numbers go in `bench/perf/results.md` (one section per group, newest first). A finished investigation is deleted once its finding is in the wiki ([index](deleted-perf-investigations-and-where-to-find-them.md)). Correctness gates that count (the `tests/checks` programs, `scaling-check`, `copy-check`) stay in `make verify`; only measurements live in the suite.

Everything lives under `bench/perf/` (Chinmay, 2026-11-25: one place, nothing to trace across directories): runners in `bench/perf/tools/`, programs beside their group, results in `results.md`. Exceptions: `workloads` reads the agent-challenge solutions, and `tools/perf-counts.ms` stays with the repository gates.
