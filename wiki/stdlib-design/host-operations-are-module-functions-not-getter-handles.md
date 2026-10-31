[Wiki](../index.md) › [Standard-library design](index.md)

# Host operations are module functions, not getter handles

Decision (Chinmay, 2026-10-31): ambient host operations are functions of their module (`read_file(path)`, not `filesystem().read_file(path)`), as in Node, Python and Go. Types stay only for configured or stateful values (a restricted `Network`, `HttpClient`). `fs` is done; `time`, `random`, `process`, `io` and `net` follow, then constants as values and package directories. `Commands`/`Entropy` injection is dropped on purpose: use plain `run`/`secure_int`. A stdlib `FileSystem` interface is private; tests that need interface defaults define their own.

Apply when: adding a host-backed operation, or touching a remaining getter (`clock()`, `network()`, `commands()`).
Evidence: [proposal](../../proposals/stdlib-host-types.md), [fs.ms](../../stdlib/fs.ms).
Verify: `ms search_symbol filesystem` finds no exported getter; `ms test tests/e2e/testdata/stdlib/fs-defaults.ms`.
