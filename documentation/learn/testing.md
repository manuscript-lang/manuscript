+++
title = "Test your code"
weight = 3
+++

# Test your code

A `test "name":` block runs under `ms test` and passes when it finishes normally. Assertions in `@std/test.ms` return `Result`s; `try` turns a failed check into the test's error. Faults (including `panic`) and timeouts also fail a test.

Save this complete file as `test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/test.ms" import expect_equal

def add(a: Int, b: Int) -> Int:
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
- Import app code with a relative path, e.g. `from "./src/math.ms" import add` ([modules](../core-language/modules/declarations.md)).
- `--filter` matches `module::name` substrings; `--timeout` bounds each test (default 60s, `0` disables).
- A bare `expect_equal(...)` statement is a check error, because a discarded `Result` checks nothing: write `try expect_equal(...)`, or `let ignored = try ...` to drop a returned value.
- `--json` emits versioned per-test results, counts, diagnostics, and stdout; it cannot combine with `--watch` ([JSON contract](../developer-tooling/implementation.md#machine-readable-checks-and-tests)).

`try expect_ok` checks success and keeps the payload:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/json.ms" import parse, JsonError
from "@std/test.ms" import expect_equal, expect_ok, expect_error, expect_some

test "typed JSON and Optional payloads":
    let number = try expect_ok(parse[Int]("3"))
    try expect_equal(number, 3)
    try expect_error(parse[Int]("true")) | try expect_equal(JsonError.InvalidData)
    try expect_some([number].first()) | try expect_equal(3)
```

Tests can also propagate errors from calls whose error type implements `Error`. See [Results](../core-language/errors/results.md).

## Select and repeat

```sh
ms test ms.toml --list
ms test ms.toml --test 'tests/math_test.ms::addition' --json
ms test ms.toml --match 'addition|zero' --exclude 'slow' --fail-fast
ms test ms.toml --repeat 10 --shuffle 42
```

- Copy exact `module::name` identities from `--list`; repeat `--test` to select several.
- `--filter`, `--match`, and `--exclude` narrow the selection; regexes match any part of the identity. Empty selections fail.
- `--list` builds but never runs test bodies.
- Each repetition starts a fresh root execution; globals and external fixtures stay shared. `--shuffle` takes a seed.
- `--fail-fast` leaves remaining tests `not_run` in JSON.

## Property tests and fuzzing

A property test checks a rule on many generated inputs instead of a few hand-picked ones. `check` in `@std/test/property.ms` takes a name, a generator, and a function that returns a `Result` like any assertion. It runs 100 cases by default.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/test/property.ms" import check, ints, lists
from "@std/test.ms" import expect_equal

test "reversing twice restores a list":
    try check("reverse twice", lists(ints(-100, 100)), lambda xs: expect_equal(xs.reversed().reversed(), xs))
```

When a case fails, `check` shrinks the input to a small counterexample and fails the test with it and the case seed:

```text
FAIL test.ms::small sums: property 'small sums' failed after 3 cases (case seed 2039066943738375196; rerun with --seed 2039066943738375196)
counterexample: [50]
expected true, got false
```

- Generators: `ints(low, high)`, `bools()`, `floats(low, high)`, `strings(alphabet, max_length)`, `lists(gen, min_length, max_length)`, `optionals(gen)`, `pairs(a, b)`, `element_of(values)`, `one_of(gens)`, and `constant(value)`.
- Combine them with the `Gen` methods `map`, `zip`, `flat_map`, and `filter`, as on lists: `ints(1, 9).map(lambda n: n * 2)`. A `filter` that cannot find a kept value discards the case; too many discards fail the test.
- Shrinking is automatic for every generator, including your own compositions: generators draw from a recorded stream of integers and shrinking edits and replays it. Integers shrink toward 0, lists toward fewer elements, `optionals` toward `none`, `bools` toward `False`.
- A generator value moves into the generator that uses it, so build a fresh `ints(...)` for each use rather than reusing one binding.
- A `panic` inside a property counts as a failing case and shrinks like a returned error; each case runs under `expect_fault`.

`ms test` controls property runs from the command line:

```sh
ms test ms.toml --runs 1000          # cases per property
ms test ms.toml --seed 2039066943738375196   # replay a reported failure
ms test ms.toml --fuzz 30s           # keep generating fresh cases for 30s per property
```

`--fuzz` replaces the case count with a time budget for each `check` call and prints the starting seed to standard error, so a fault that kills the process can still be replayed with `--seed`. It disables the default 60s `--timeout` unless you pass one. An explicit `seed:` argument to `check` overrides `--seed`. The [property-testing example](https://github.com/manuscript-lang/manuscript/tree/main/examples/property-testing) shows a project with several properties.

All assertions return `Result`, so use `try`:

- `expect_some`, `expect_ok`, `expect_error` yield the checked payload.
- `expect_fault(operation)` checks programming faults.
- `fail(message)` fails explicitly; `skip(reason)` skips while running cleanup.
- Write each independently reported case as its own `test` block.

## Profile application work

Use `ms profile` on a runnable project with an exported `main`:

```sh
ms profile ms.toml --out-dir capture --top 10
```

This runs the application entry point, not its test blocks. Put the workload you want to measure in the application's execution path. `capture` must be a new directory; the sampling profile includes folded stacks, pprof data, and a text report. The default build type is `Release`. See [profiling and native debugging](../developer-tooling/debugging/debugger-integration.md) for output files and source-attribution limits.

## Shared setup and teardown

Without `make_fixture`, no hooks run. Define `def make_fixture() -> T` where `T` implements `TestHooks` from `@std/test.ms`; tests then read it as `fixture`.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/test.ms" import TestHooks, expect_equal

type Counter:
    count: Int

def make_fixture() -> Counter:
    return Counter(0)

impl TestHooks for Counter:
    var def before_each() -> Unit:
        self.count = 0

test "increments":
    fixture.count += 1
    try expect_equal(fixture.count, 1)

test "starts fresh":
    try expect_equal(fixture.count, 0)
```

`make_fixture` runs once per file. `before_each` resets the shared `Counter` before every test, so the second test sees `0` even though the first changed it.

- One instance per file, created only when the file has selected tests and shared across repetitions.
- Optional hooks (use `self`, no arguments, return `Unit`): `before_all`, `before_each`, `after_each`, `after_all`.
- Build in `make_fixture`, reset in `before_each`, release in `after_all`.
