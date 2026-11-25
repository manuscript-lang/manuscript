[Wiki](../index.md) › [Benchmarks and performance](index.md)

# There is one perf suite, indexed by `bench/perf/groups.txt`

Decision (Chinmay, 2026-11-25): perf tests were scattered over `bench/`, `bench/perf/` and `tests/`, so they are one suite with one runner (`make perf-list`, `make perf GROUP=<name>`, `bench/tools/perf.ms`) and one index, [`groups.txt`](../../../bench/perf/groups.txt). Each group has a kind, a command and a results page; `make perf-check` (part of `make bench-check`) fails on a group without a results page or README row, and on a path under `bench/perf/` in neither `groups.txt` nor `investigations.txt`.

A new benchmark is a row in `groups.txt` and in the `bench/perf/README.md` table. A finished investigation goes in `investigations.txt`. `bench/language`, `bench/lists` and `bench/lowering` stay put: conformance fixtures name those paths. Correctness gates that count (the `tests/checks` programs, `scaling-check`, `copy-check`) stay in `make verify`; only measurements live in the suite.
