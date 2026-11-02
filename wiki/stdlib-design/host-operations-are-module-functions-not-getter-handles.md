[Wiki](../index.md) › [Standard-library design](index.md)

# Host operations are module functions, not getter handles

Decision (Chinmay, 2026-10-31): ambient host operations are functions of their module (`read_file(path)`, not `filesystem().read_file(path)`), as in Node, Python and Go. Types stay only for configured or stateful values (a restricted `Network`, `HttpClient`). `fs`, `time`, `random`, `process`, `io` and `net` are converted; the host-handle interfaces are private (`Network` stays exported because `restrict` and `with_resolver` return one). `Commands` stays an exported interface only as the shape of `run`/`spawn`. `stdin()`, `stdout()` and `stderr()` remain getters of the shared stream.

Follow-on rules from the same change:
- Constants are values only when they are literals: `math.pi`, `max_int` are `export let`; `os_type()`, `end_of_line()` stay functions because a constant cannot call a native.
- `ordering.ms` has one `Ordered` interface using `Self`; interfaces cannot have default method bodies or generic methods, so each scalar still has a small `impl`.
- A private helper whose first parameter is a local type becomes a method on it (`csv`, `sse`, `jsonstream`). Methods cannot take other `var` parameters, and converting `toml` and `yaml` panics with "cyclic standard source dependency", so those two keep free functions.
- Every extern fn lives in `stdlib/internal/<module>.ms` (not importable by programs, hidden from docs). An internal module imports its host's types, private ones too, and the pair is checked as one group. Exception: `extern type` stays in its host (inherent methods belong there). A bodiless native that is a plain runtime call is an extern in internal plus a wrapper in the host (bytes `join`, string `compile`, list `filled`); compiler-lowered intrinsics (`range`, `panic`, `share`, `map_from_entries`, `category`, `test.*`) stay declarations because lowering matches their native identity. A public name that only the `+source` half of a mixed file declares is importable under the file's own path.
- Modules sit in packages (`net/`, `io/`, `os/`, `data/`, `collections/`, `concurrency/`, `math/`, `test/`); `@std/net/http.ms`. Native identifiers use the module stem without the package (`ms-check` `module_stem`), so `ms search_symbol http` still works.

Apply when: adding a host-backed operation, a constant, or a module.
Evidence: [proposal](../../proposals/stdlib-host-types.md), [fs.ms](../../stdlib/os/fs.ms), [internal natives](../../stdlib/internal/math.ms).
Verify: `ms search_symbol filesystem` finds no exported getter; `ms check` on `filesystem()` prints the removed-getter hint; `ms test tests/e2e/testdata/stdlib/fs-defaults.ms`.
