+++
title = "Test your code"
weight = 3
+++

# Test your code

A `test "name":` block runs under `ms test` and passes when it finishes normally. For timing, see [Benchmark your code](#benchmark-your-code). Assertions in `@std/test/test.ms` return `Result`s; `try` turns a failed check into the test's error. Faults (including `panic`) and timeouts also fail a test.

Save this complete file as `test.ms`:

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::addition\nPASS test.ms::addition\nRUN test.ms::zero is unchanged\nPASS test.ms::zero is unchanged\n2 tests, 0 failed\n","cases":[{"args":["--filter","addition"],"stdout":"RUN test.ms::addition\nPASS test.ms::addition\n1 tests, 0 failed\n"},{"args":["--list"],"stdout":"test.ms::addition\ntest.ms::zero is unchanged\n"}]} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn add(a: Int, b: Int) Int:
    return a + b

test "addition":
    try expect_equal(add(1, 2), 3)

test "zero is unchanged":
    try expect_equal(add(0, 7), 7)
```

```sh
ms test test.ms
```

```text
RUN test.ms::addition
PASS test.ms::addition
RUN test.ms::zero is unchanged
PASS test.ms::zero is unchanged
2 tests, 0 failed
```

Select one test or set a per-test deadline:

```sh
ms test test.ms --filter addition
ms test test.ms --timeout 10s
```

With `--filter addition`, only the selected test runs:

```text
RUN test.ms::addition
PASS test.ms::addition
1 tests, 0 failed
```

`expect_equal` works with numbers, text, collections, and `Equal` types; `assert_equal` is the TDD spelling. Change `3` to `4` to see `FAIL test.ms::addition: expected 4, got 3` and a nonzero exit. A tests file needs no `main`.

## Run tests in a project

For a project created with `ms init` in [getting started](getting-started.md), save the opening two-test example as `test.ms` beside `ms.toml`. Run these commands from that project directory:

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
- A bare `expect_equal(...)` statement is a check error, because a discarded `Result` checks nothing: write `try expect_equal(...)`, or `let _ = try ...` to drop a returned value.
- `--json` emits versioned per-test results, counts, diagnostics, and stdout; it cannot combine with `--watch` ([JSON contract](../developer-tooling/implementation.md#machine-readable-checks-and-tests)).

For each standalone test example below, replace the contents of `test.ms` and run `ms test test.ms`. `try expect_ok` checks success and keeps the payload:

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::typed JSON and Optional payloads\nPASS test.ms::typed JSON and Optional payloads\n1 tests, 0 failed\n"} -->
```manuscript
import parse from "@std/data/json.ms"
import expect_equal, expect_ok, expect_error, expect_some from "@std/test/test.ms"

test "typed JSON and Optional payloads":
    let number = try expect_ok(parse[Int]("3"))
    try expect_equal(number, 3)
    let cause = try expect_error(parse[Int]("true"))
    try expect_equal(cause.kind, "EBADMSG")
    try expect_some([number].first()) | try expect_equal(3)
```

Test output:

```text
RUN test.ms::typed JSON and Optional payloads
PASS test.ms::typed JSON and Optional payloads
1 tests, 0 failed
```

Tests can also propagate an `Error` with `try`. See [Results](../core-language/errors/results.md).

## Select and repeat

With the opening `addition` and `zero is unchanged` tests saved in `test.ms`, list their exact names:

```sh
ms test test.ms --list
```

```text
test.ms::addition
test.ms::zero is unchanged
```

Run one named test, select names with a pattern, or repeat the suite in a seeded order:

```sh
ms test test.ms --test 'test.ms::addition' --json
ms test test.ms --match 'addition|zero' --exclude 'slow' --fail-fast
ms test test.ms --repeat 10 --shuffle 42
```

- Copy exact `module::name` identities from `--list`; repeat `--test` to select several.
- `--filter`, `--match`, and `--exclude` narrow the selection; regexes match any part of the identity. Empty selections fail.
- `--list` builds but never runs test bodies.
- Each selected test and repetition runs in a fresh process. In-memory state is isolated; external files and services remain shared unless the test resets them. `--shuffle` takes a seed.
- `--fail-fast` leaves remaining tests `not_run` in JSON.

## Property tests and fuzzing

A property test checks a rule on many generated inputs instead of a few hand-picked ones. `check` in `@std/test/property.ms` takes a name, a generator, and a function that returns a `Result` like any assertion. It runs 100 cases by default.

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::reversing twice restores a list\nPASS test.ms::reversing twice restores a list\n1 tests, 0 failed\n"} -->
```manuscript
import check, ints, lists from "@std/test/property.ms"
import expect_equal from "@std/test/test.ms"

test "reversing twice restores a list":
    try check("reverse twice", lists(ints(-100, 100)), fn xs: expect_equal(xs.reversed().reversed(), xs))
```

Test output:

```text
RUN test.ms::reversing twice restores a list
PASS test.ms::reversing twice restores a list
1 tests, 0 failed
```

When a case fails, `check` shrinks the input to a small counterexample and reports the case seed. Replace `test.ms` with this deliberately false property and run `ms test test.ms`. It claims that every generated list sums to less than 50; the fixed seed makes this failure reproducible:

<!-- manuscript-example: {"mode":"test","filename":"test.ms","exit_code":1,"stdout":"RUN test.ms::small sums\nFAIL test.ms::small sums: property 'small sums' failed after 1 cases (case seed 11; rerun with --seed 11)\ncounterexample: [50]\nexpected true, got false\n  at test.ms:7:16\n1 tests, 1 failed\n"} -->
```manuscript
import check, ints, lists from "@std/test/property.ms"
import expect_true from "@std/test/test.ms"

test "small sums":
    try check(
        "small sums", lists(ints(0, 1000)),
        fn xs: expect_true(xs.sum() < 50), seed: 11
    )
```

The command exits with status 1 and prints:

```text
RUN test.ms::small sums
FAIL test.ms::small sums: property 'small sums' failed after 1 cases (case seed 11; rerun with --seed 11)
counterexample: [50]
expected true, got false
  at test.ms:7:16
1 tests, 1 failed
```

The one-item list `[50]` is enough to disprove the claim. Correct the property or the implementation under test before keeping it in a passing suite. To replay a reported command-line seed, remove the explicit `seed:` argument first; an explicit argument takes precedence.

- Generators: `ints(low, high)`, `bools()`, `floats(low, high)`, `strings(alphabet, max_length)`, `lists(gen, min_length, max_length)`, `optionals(gen)`, `pairs(a, b)`, `element_of(values)`, `one_of(gens)`, and `constant(value)`.
- Combine them with the `Gen` methods `map`, `zip`, `flat_map`, and `filter`, as on lists: `ints(1, 9).map(fn n: n * 2)`. A `filter` that cannot find a kept value discards the case; too many discards fail the test.
- Shrinking is automatic for every generator, including your own compositions: generators draw from a recorded stream of integers and shrinking edits and replays it. Integers shrink toward 0, lists toward fewer elements, `optionals` toward `none`, `bools` toward `false`.
- A generator value moves into the generator that uses it, so build a fresh `ints(...)` for each use rather than reusing one binding.
- A `panic` inside a property counts as a failing case and shrinks like a returned error; each case runs under `expect_fault`.

To exercise command-line controls in that project, replace its `test.ms` with the passing “reversing twice restores a list” example above:

```sh
ms test ms.toml --runs 1000          # cases per property
ms test ms.toml --seed 11          # use a reported case seed
ms test ms.toml --fuzz 30s           # keep generating fresh cases for 30s per property
```

`--fuzz` replaces the case count with a time budget for each `check` call and prints the starting seed to standard error, so a fault that kills the process can still be replayed with `--seed`. It disables the default 60s `--timeout` unless you pass one. An explicit `seed:` argument to `check` overrides `--seed`. The [property-testing example](https://github.com/manuscript-lang/manuscript/tree/main/examples/property-testing) shows a project with several properties.

All assertions return `Result`, so use `try`:

- `expect_some`, `expect_ok`, `expect_error` yield the checked payload.
- `expect_fault(operation)` checks programming faults.
- `fail(message)` fails explicitly; `skip(reason)` skips while running cleanup.
- Write each independently reported case as its own `test` block.

## Golden files and misbehaving streams

`expect_golden(path, actual)` in `@std/test/golden.ms` compares text with a file kept next to the test and names the first differing line on a mismatch. Run `MS_UPDATE_GOLDEN=1 ms test ...` to rewrite the files from the actual output, review the change in version control, then run again without it. `expect_golden_bytes` does the same for bytes.

`@std/test/iotest.ms` wraps streams to test code that reads and writes: `one_byte(input)` trickles one byte per read, `fail_after(input, n, cause)` fails every read after `n` bytes, and `fail_writer_after(output, n, cause)` fails like a full disk. `check_reader(make, expected)` checks a `ReadStream` you wrote: whole reads, one-byte reads, a respected chunk size, and an end of input that stays ended.

## Benchmark your code

A `bench "name":` block works like a `test` block, but `ms bench` times it instead of checking it. The body is one iteration; `ms bench` repeats it until a sample takes about 100ms (that calibration is also the warmup), takes ten samples, and reports the time per iteration. `ms test` skips bench blocks. Save this complete file as `bench.ms`:

<!-- manuscript-example: {"mode":"bench","filename":"bench.ms"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn sum_to(n: Int) Int:
    var total = 0
    for i in 0..n:
        total += i
    return total

bench "sum to one hundred":
    try expect_equal(sum_to(100), 4950)
```

```sh
ms bench bench.ms
ms bench bench.ms --time 500ms --samples 20
```

To select benchmarks from a project, put the same `bench.ms` beside its `ms.toml` and run:

```sh
ms bench ms.toml --filter "sum" --json
```

- A project loads `bench.ms` and `*_bench.ms` files; a bench may also sit in any module the command loads. Benches take the same selection options as tests (`--filter`, `--match`, `--exclude`, `--bench`, `--list`, `--repeat`, `--fail-fast`, `--timeout`).
- `--time` sets the target length of one sample, `--samples` the number of timed samples, and `--iterations` fixes the iteration count and skips calibration.
- `bench "name" per 1000:` declares that one iteration performs 1000 operations (a loop over 1000 items, say); every statistic is then per operation. `keep(value)` from `@std/test/bench.ms` checks a computed `Int` so the work stays observable.
- To keep setup out of the timing, build the data first and time only the work: `try measure(1000, fn: keep(data.sorted().length()))` from `@std/test/bench.ms` runs the work repeatedly and reports per operation, here for 1000 operations per run. Everything before `measure` runs once, untimed.
- Each bench runs in its own process. A body that returns an error, faults, or exceeds `--timeout` (default 10 minutes) fails that bench and the exit status is 1. Standard output written by a bench is discarded.
- `--json` adds `stats` to each entry of `benches`: `iterations`, `operations`, `samples`, and `min_ns`, `median_ns`, `mean_ns`, `max_ns`, `stddev_ns` in nanoseconds per operation (per iteration when `operations` is 1).
- Keep the measured work in the body and the setup outside it: a bench has no `fixture` and no hooks. Check a result with `try` so the compiler cannot discard the work; benchmark the default `Release` build.

## Profile application work

Use `ms profile` on a runnable project with an exported `main`:

```sh
ms profile ms.toml --out-dir capture --top 10
```

This runs the application entry point, not its test blocks. Put the workload you want to measure in the application's execution path. `capture` must be a new directory; the sampling profile includes folded stacks, pprof data, and a text report. The default build type is `Release`. See [profiling and native debugging](../developer-tooling/debugging/debugger-integration.md) for output files and source-attribution limits.

## Shared setup and teardown

Without `make_fixture`, no hooks run. Define `fn make_fixture() T` where `T` implements `TestHooks` from `@std/test/test.ms`; tests then read it as `fixture`.

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::increments\nPASS test.ms::increments\nRUN test.ms::starts fresh\nPASS test.ms::starts fresh\n2 tests, 0 failed\n"} -->
```manuscript
import TestHooks, expect_equal from "@std/test/test.ms"

type Counter:
    count: Int

fn make_fixture() Counter:
    return Counter(0)

impl TestHooks for Counter:
    var fn before_each() Unit:
        self.count = 0

test "increments":
    fixture.count += 1
    try expect_equal(fixture.count, 1)

test "starts fresh":
    try expect_equal(fixture.count, 0)
```

Test output:

```text
RUN test.ms::increments
PASS test.ms::increments
RUN test.ms::starts fresh
PASS test.ms::starts fresh
2 tests, 0 failed
```

`ms test` starts a separate process for each selected test. Each process creates its own fixture and runs its hooks, so the second test starts from a fresh `Counter`. The same isolation applies to repetitions.

- One instance for the selected test in its process; the factory and `before_all` run again for the next test or repetition.
- Optional hooks (use `self`, no arguments, return `Unit`): `before_all`, `before_each`, `after_each`, `after_all`.
- Build in `make_fixture`, reset in `before_each`, release in `after_all`.

## Run tests only on some platforms

There is no platform attribute on `test` blocks. Skip at run time instead, comparing `os_type()` from `@std/os/process.ms` (`Linux`, `Darwin`, or `Windows_NT`). The file must still compile on every platform.

To skip a single test, call `skip` in its body. Save this complete file as `test.ms`; it checks the host line-ending API on Unix:

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout_by_os":{"default":"RUN test.ms::unix line ending\nPASS test.ms::unix line ending\n1 tests, 0 failed\n","windows":"RUN test.ms::unix line ending\nSKIP test.ms::unix line ending: Unix only\n1 tests, 0 failed, 1 skipped\n"}} -->
```manuscript
import skip, expect_equal from "@std/test/test.ms"
import os_type, end_of_line from "@std/os/process.ms"

test "unix line ending":
    if os_type() == "Windows_NT":
        skip("Unix only")
    try expect_equal(end_of_line(), "\n")
```

Run `ms test test.ms`. On Linux and macOS, it prints:

```text
RUN test.ms::unix line ending
PASS test.ms::unix line ending
1 tests, 0 failed
```

To skip every test in a file, call `skip` from a fixture hook. `before_all` and `before_each` both work; `after_all` and `after_each` still run, and each test is reported as `SKIP` with your reason:

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout_by_os":{"default":"RUN test.ms::windows line ending\nSKIP test.ms::windows line ending: Windows only\n1 tests, 0 failed, 1 skipped\n","windows":"RUN test.ms::windows line ending\nPASS test.ms::windows line ending\n1 tests, 0 failed\n"}} -->
```manuscript
import TestHooks, skip, expect_equal from "@std/test/test.ms"
import os_type, end_of_line from "@std/os/process.ms"

type WindowsOnly:
    ok: Bool

fn make_fixture() WindowsOnly:
    return WindowsOnly(os_type() == "Windows_NT")

impl TestHooks for WindowsOnly:
    var fn before_all() Unit:
        if not self.ok:
            skip("Windows only")

test "windows line ending":
    try expect_equal(end_of_line(), "\r\n")
```

Replace `test.ms` with this second complete file and run `ms test test.ms`. On Linux, the fixture skips the test before its Windows assertion runs:

```text
RUN test.ms::windows line ending
SKIP test.ms::windows line ending: Windows only
1 tests, 0 failed, 1 skipped
```

On Windows, the test instead checks the host’s CRLF line ending. Skipped tests are counted in the summary, so a platform that runs nothing stays visible. These examples demonstrate runtime selection; they do not establish that the Windows or macOS assertions have run on another host.
