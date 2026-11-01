[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Benchmark drivers are `ms run` programs in the flat `bench/tools/` directory

Decision (2026-10-31, Chinmay): benchmark runners, table builders and comparison drivers are Manuscript files run with `ms run bench/tools/<name>.ms [-- args]`, not shell or Python. A file target now takes its import root and aliases from the nearest enclosing `ms.toml` (#2163), so drivers may sit beside their suites and import a shared library above them; the existing drivers still live flat in `bench/tools/` beside `lib.ms` until they are moved. Tests are `*_test.ms` files run with `ms test`; `make bench-check` checks and tests them.

Verified: `run`/`spawn` take `cwd` and `env` and report the child's peak resident set (`CommandOutput.max_resident_bytes`, `Subprocess.max_resident_bytes()`), so drivers use `lib.run_in`/`lib.peak_run` without changing process-wide state; `@std/os/random.seeded` replaces hand-written generators (`rss.c` stays only for the Python runner `bench/perf/representative/run.py`); a JSON `Map` field is not `Data` (build reports from `JsonValue`). The benchmark projects had silently rotted (`Optional[T]`, removed `FileSystem`) because nothing ran them; run a driver after changing the language.

Apply when: adding or changing a benchmark driver or a table with its evidence checks.
Evidence: [bench/tools](../../bench/tools/lib.ms).
