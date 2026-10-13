+++
title = "Testing"
weight = 4
+++

# Testing

A `test "name":` block runs when you invoke `ms test`. A block passes when it finishes normally; `panic` from `@std/faults.ms` fails it with a message. There is no `assert` statement or built-in `expect` function. Write a condition that calls `panic`, or define a helper for the values you compare.

Save this complete file as `test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

fn add(a: Int, b: Int) -> Int:
    return a + b

fn expect_equal(actual: Int, expected: Int) -> Unit:
    if actual != expected:
        return panic("Expected {expected}, got {actual}")

test "addition":
    expect_equal(add(1, 2), 3)

test "zero is unchanged":
    let actual = add(0, 7)
    if actual != 7:
        return panic("Expected 7, got {actual}")
```

```sh
ms test test.ms
ms test test.ms --filter addition
ms test test.ms --timeout 10s
```

The helper is an ordinary function specialized for `Int`. Define a helper with the appropriate parameter types when testing text or another type. It evaluates the actual and expected values once and includes both in its failure message. `return panic(...)` stops the test; `panic` never returns normally.

To see a failure, change the first test's expected value from `3` to `4`. The CLI prints a line containing `FAIL test.ms::addition: Expected 4, got 3`, reports one failed test, and returns a nonzero exit status. Restore `3` to make both tests pass. There is no need for `main` in a tests file, and `ms test` does not execute an application's `main`.

## Run tests in a project

```sh
ms test ms.toml
ms test ms.toml --filter addition --timeout 10s
```

A manifest run discovers `test.ms` and `*_test.ms` files recursively below the project root, as well as tests in imported modules. A direct `ms test file.ms` runs that module's tests and the tests in its imports; it does not discover unrelated sibling files. The exact traversal and excluded-directory rules live in [project configuration](../developer-tooling/builds/project-configuration.md#commands-and-module-discovery).

Tests run from the manifest's directory, or from the selected source file's directory for a single-file run. Relative fixture paths therefore resolve consistently when you invoke `ms test` from another directory; see [build and test](getting-started.md#build-and-test).

Put reusable application functions in an exported module and import them into a test file with a relative path, for example `import add from "./src/math.ms"`. Keep the import consistent with your project's actual files; see [modules](../core-language/modules/declarations.md).

`--filter` selects tests whose `module::name` contains the supplied text. `--timeout` bounds each test (60 seconds by default; `0` disables it). A programming fault or timeout fails the test; a function returning `error(...)` is still an ordinary value that you must check. Do not discard a `Result` when testing success or failure.

For example, this fragment belongs inside a test after calling a fallible function:

```manuscript
match result:
    ok(value):
        expect_equal(value, 3)
    error(cause):
        return panic("Expected success, got {cause.message()}")
```

The fragment assumes `Result[Int, Error]` and the `Int` helper above. Handle domain-specific error cases explicitly when a test is meant to check a failure. See [Results](../core-language/errors/results.md) and [programming faults](../core-language/errors/faults.md).
