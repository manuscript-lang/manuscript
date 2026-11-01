[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Benchmark drivers are `ms run` programs in the flat `bench/tools/` directory

Decision (2026-10-31, Chinmay): benchmark runners, table builders and comparison drivers are Manuscript files run with `ms run bench/tools/<name>.ms [-- args]`, not shell or Python. A file target now takes its import root and aliases from the nearest enclosing `ms.toml` (#2163), so drivers may sit beside their suites and import a shared library above them; the existing drivers still live flat in `bench/tools/` beside `lib.ms` until they are moved. Tests are `*_test.ms` files run with `ms test`; `make bench-check` checks and tests them.

Verified: `commands().run` has no working-directory or environment parameter (use `lib.run_in`, which changes the process-wide directory), `ResourceUsage` describes only the caller (child peak RSS still goes through `bench/perf/representative/rss.c`), `@std/random` has no seeded generator (generators write a small LCG), and a JSON `Map` field is not `Data` (build reports from `JsonValue`). The benchmark projects had silently rotted (`Optional[T]`, removed `FileSystem`) because nothing ran them; run a driver after changing the language.

Apply when: adding or changing a benchmark driver or a table with its evidence checks.
Evidence: [bench/tools](../../bench/tools/lib.ms).
