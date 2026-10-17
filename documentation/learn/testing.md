+++
title = "Test your code"
weight = 3
+++

# Test your code

A `test "name":` block runs when you invoke `ms test`. A block passes when it finishes normally. A block fails when it returns an `error(...)`: the helpers in `@std/testing.ms` return `Result` values, and `try` returns a failed check as the test's error. A test body behaves as if it returns `Result[Unit, Error]`; you never need to write that, and completing without a `return` is success. A programming fault (including `panic`) or a timeout also fails the test, but prefer returning errors. Import reusable TDD assertions or BDD expectations from `@std/testing.ms`.

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

The generic equality helper works with numbers, text, collections, and types implementing `Equal`. It evaluates arguments once and reports expected and actual values. `assert_equal` provides the equivalent TDD spelling.

To see a failure, change the first test's expected value from `3` to `4`. The CLI prints a line containing `FAIL test.ms::addition: expected 4, got 3`, reports one failed test, and returns a nonzero exit status. Restore `3` to make both tests pass. There is no need for `main` in a tests file, and `ms test` does not execute an application's `main`.

## Run tests in a project

```sh
ms test ms.toml
ms test ms.toml --filter addition --timeout 10s
ms test ms.toml --json
```

A manifest run discovers `test.ms` and `*_test.ms` files recursively below the project root, as well as tests in imported modules. A direct `ms test file.ms` runs that module's tests and the tests in its imports; it does not discover unrelated sibling files. The exact traversal and excluded-directory rules live in [project configuration](../developer-tooling/builds/project-configuration.md#commands-and-module-discovery).

Tests run from the manifest's directory, or from the selected source file's directory for a single-file run. Relative fixture paths therefore resolve consistently when you invoke `ms test` from another directory; see [build and test](getting-started.md#build-and-test).

Put reusable application functions in an exported module and import them into a test file with a relative path, for example `import add from "./src/math.ms"`. Keep the import consistent with your project's actual files; see [modules](../core-language/modules/declarations.md).

`--filter` selects tests whose `module::name` contains the supplied text. `--timeout` bounds each test (60 seconds by default; `0` disables it). A programming fault or timeout fails the test; a function returning `error(...)` is still an ordinary value that you must check. Do not discard a `Result` when testing success or failure; assertions are `Result`s too, so a bare `expect_equal(...)` statement checks nothing. Write `try expect_equal(...)`.

For automation, `--json` emits a versioned result with per-test outcomes, counts,
source diagnostics and captured stdout. Stderr remains stderr; failures keep
their exit status. It supports one run and cannot be combined with `--watch`.
See the [JSON contract](../developer-tooling/implementation.md#machine-readable-checks-and-tests).

Use `try expect_ok` to check success and keep its payload. This complete example
also checks a failure and unwraps an Optional without an unchecked `unwrap()`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {parse, JsonError} from "@std/json.ms"
import {expect_equal, expect_ok, expect_error, expect_some} from "@std/testing.ms"

test "typed JSON and Optional payloads":
    let number = try expect_ok(parse[Int]("3"))
    try expect_equal(number, 3)
    try expect_error(parse[Int]("true")) | try expect_equal(JsonError.InvalidData)
    try expect_some([number].at(0)) | try expect_equal(3)
```

Use `try` on every expectation to return a failed check as the test’s error.
Tests can also propagate errors from other calls when their error type implements
`Error`; convert other error types explicitly. See
[Results](../core-language/errors/results.md) and the
[testing helper reference](../standard-library/testing.md) for other assertions.

## Select, repeat, and profile

```sh
ms test ms.toml --list
ms test ms.toml --test 'tests/math_test.ms::addition' --json
ms test ms.toml --match 'addition|zero' --exclude 'slow' --fail-fast
ms test ms.toml --repeat 10 --shuffle 42
ms test ms.toml --filter addition --cpu-profile cpu.pprof --heap-profile heap.pprof --trace trace.out
ms pprof -top cpu.pprof
```

Copy exact `module::name` identities from `--list`. Repeating `--test` selects
several exact names. Exact selections form a union; `--filter`, `--match` and
`--exclude` further restrict that union. Inclusion and exclusion regexes match
any part of the full identity. Unknown exact names and empty selections fail.
Listing checks and builds source but never invokes test bodies. Each repetition
uses a fresh root execution; process globals and external fixtures remain shared.
Shuffle uses the supplied integer seed, and repeats use the same shuffled order.
Fail-fast leaves the remaining selected executions as `not_run` in JSON.

Profiling captures the selected tests in one process, including runner and cleanup
cost. Capture paths resolve from the CLI invocation directory and must be new. Profiles flush even when assertions fail. `--list` and
`--watch` cannot be combined with profiling. Longer or repeated tests yield more
useful CPU samples; profiling adds overhead. Profiled tests default to
`RelWithDebInfo`; `--build-type` can select another build.

Every assertion returns `Result[..., Error]`, so use `try`. `try expect_some(x)`, `try expect_ok(x)`, and `try expect_error(x)` yield the checked payloads;
`try expect_fault(operation)` checks programming faults. `try fail(message)` fails a test explicitly. `skip(reason)` marks a test skipped
while running lexical cleanup. Write each independently selected and reported
case as a `test` block. See the
[testing helper reference](../standard-library/testing.md) for contracts and examples.

## Shared setup and teardown

Without a local `make_fixture`, tests run normally and no lifecycle hooks run.

A test file can define `fn make_fixture() -> T`, where the concrete return type
implements `TestHooks` from `@std/testing.ms`. The runner creates one instance
for the file, and its test blocks access it as `fixture`. Hooks use `self`.
The optional hooks are `before_all`, `before_each`, `after_each`, and `after_all`;
all take no arguments and return `Unit`.

Put construction in `make_fixture`, reset shared state in `before_each`, and
release resources in `after_all`. The instance is created only when the file
has selected tests, and remains shared across repetitions. See
[file fixtures](../standard-library/testing.md#file-fixtures) for a complete
example, failure handling, timeout behavior, and cancellation cleanup.
