+++
title = "Test your code"
weight = 3
+++

# Test your code

A `test "name":` block runs under `ms test` and passes when it finishes normally. Assertions in `@std/testing.ms` return `Result`s; `try` turns a failed check into the test's error. Faults (including `panic`) and timeouts also fail a test.

Save this complete file as `test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal} from "@std/testing.ms"

fn add(a: Int, b: Int) -> Int:
    return a + b

test "addition":
    try expect_equal(add(1, 2), 3)

test "zero is unchanged":
    try expect_equal(add(0, 7), 7)
```

```sh
ms test test.ms
ms test test.ms --filter addition
ms test test.ms --timeout 10s
```

`expect_equal` works with numbers, text, collections, and `Equal` types; `assert_equal` is the TDD spelling. Change `3` to `4` to see `FAIL test.ms::addition: expected 4, got 3` and a nonzero exit. A tests file needs no `main`.

## Run tests in a project

```sh
ms test ms.toml
ms test ms.toml --filter addition --timeout 10s
ms test ms.toml --json
```

- A manifest run discovers `test.ms` and `*_test.ms` files below the project root, plus tests in imports ([discovery rules](../developer-tooling/builds/project-configuration.md#commands-and-module-discovery)).
- `ms test file.ms` runs that module and its imports only.
- Tests run from the manifest's directory (or the file's, for a single file), so relative fixture paths are stable; see [build and test](getting-started.md#build-and-test).
- Import app code with a relative path, e.g. `import add from "./src/math.ms"` ([modules](../core-language/modules/declarations.md)).
- `--filter` matches `module::name` substrings; `--timeout` bounds each test (default 60s, `0` disables).
- A bare `expect_equal(...)` checks nothing: always write `try expect_equal(...)`.
- `--json` emits versioned per-test results, counts, diagnostics, and stdout; it cannot combine with `--watch` ([JSON contract](../developer-tooling/implementation.md#machine-readable-checks-and-tests)).

`try expect_ok` checks success and keeps the payload:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {parse, JsonError} from "@std/json.ms"
import {expect_equal, expect_ok, expect_error, expect_some} from "@std/testing.ms"

test "typed JSON and Optional payloads":
    let number = try expect_ok(parse[Int]("3"))
    try expect_equal(number, 3)
    let cause = try expect_error(parse[Int]("true"))
    try expect_equal(cause, JsonError.InvalidData)
    let first = try expect_some([number].at(0))
    try expect_equal(first, 3)
```

Tests can also propagate errors from calls whose error type implements `Error`. See [Results](../core-language/errors/results.md).

## Select, repeat, and profile

```sh
ms test ms.toml --list
ms test ms.toml --test 'tests/math_test.ms::addition' --json
ms test ms.toml --match 'addition|zero' --exclude 'slow' --fail-fast
ms test ms.toml --repeat 10 --shuffle 42
ms test ms.toml --filter addition --cpu-profile cpu.pprof --heap-profile heap.pprof --trace trace.out
ms pprof -top cpu.pprof
```

- Copy exact `module::name` identities from `--list`; repeat `--test` to select several.
- `--filter`, `--match`, and `--exclude` narrow the selection; regexes match any part of the identity. Empty selections fail.
- `--list` builds but never runs test bodies.
- Each repetition starts a fresh root execution; globals and external fixtures stay shared. `--shuffle` takes a seed.
- `--fail-fast` leaves remaining tests `not_run` in JSON.
- Profiling covers the selected tests in one process; output paths must be new, and `--list` and `--watch` cannot combine with it. Profiled tests default to `RelWithDebInfo` (`--build-type` overrides).

All assertions return `Result`, so use `try`:

- `expect_some`, `expect_ok`, `expect_error` yield the checked payload.
- `expect_fault(operation)` checks programming faults.
- `fail(message)` fails explicitly; `skip(reason)` skips while running cleanup.
- Write each independently reported case as its own `test` block.

## Shared setup and teardown

Without `make_fixture`, no hooks run. Define `fn make_fixture() -> T` where `T` implements `TestHooks` from `@std/testing.ms`; tests then read it as `fixture`.

- One instance per file, created only when the file has selected tests and shared across repetitions.
- Optional hooks (use `self`, no arguments, return `Unit`): `before_all`, `before_each`, `after_each`, `after_all`.
- Build in `make_fixture`, reset in `before_each`, release in `after_all`.
