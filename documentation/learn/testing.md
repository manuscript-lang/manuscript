+++
title = "Test your code"
weight = 3
+++

# Test your code

A `test "name":` block runs under `ms test` and passes when it finishes normally. For timing, see [Benchmark your code](#benchmark-your-code). Assertions in `@std/test/test.ms` return `Result`s; `?` turns a failed check into the test's error. Faults (including `panic`) and timeouts also fail a test.

Save this complete file as `test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn add(a: Int, b: Int) Int:
    return a + b

test "addition":
    expect_equal(add(1, 2), 3)?

test "zero is unchanged":
    expect_equal(add(0, 7), 7)?
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

`expect_equal` works with numbers, text, collections, and `Equal` types. Change `3` to `4` to see `FAIL test.ms::addition: expected 4, got 3` and a nonzero exit. A tests file needs no `main`.

## Run tests in a project

```sh
ms test ms.toml
ms test ms.toml --filter addition --timeout 10s
ms test ms.toml --json
```

- A manifest run discovers `test.ms` and `*_test.ms` files below the project root, plus tests in imports ([discovery rules](../developer-tooling/builds/project-configuration.md#commands-and-module-discovery)).
- `ms test file.ms` runs that module and its imports only. `ms test a.ms b.ms` builds both into one executable and runs every test in one invocation.
- Tests run from the manifest's directory (or the file's, for a single file), so relative fixture paths are stable; see [build and test](getting-started.md#build-and-test).
- Import app code with a relative path, e.g. `import add from "./src/math.ms"` ([modules](../core-language/modules/declarations.md)).
- `--filter` matches `module::name` substrings; `--timeout` bounds each test (default 60s, `0` disables).
- A bare `expect_equal(...)` statement is a check error, because a discarded `Result` checks nothing: write `expect_equal(...)?`, or `_ := ...` to drop a returned value.
- `--json` emits versioned per-test results, counts, diagnostics, and stdout; it cannot combine with `--watch` ([JSON contract](../developer-tooling/implementation.md#machine-readable-checks-and-tests)).

For each standalone test example below, replace the contents of `test.ms` and run `ms test test.ms`. `expect_ok?` checks success and keeps the payload:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import parse from "@std/data/json.ms"
import expect_equal, expect_ok, expect_error, expect_some from "@std/test/test.ms"

test "typed JSON and Optional payloads":
    number := expect_ok(parse[Int]("3"))?
    expect_equal(number, 3)?
    cause := expect_error(parse[Int]("true"))?
    expect_equal(cause.kind, "EBADMSG")?
    expect_some([number].first())? | expect_equal(3)?
```

Test output:

```text
RUN test.ms::typed JSON and Optional payloads
PASS test.ms::typed JSON and Optional payloads
1 tests, 0 failed
```

Tests can also propagate an `Error` with `?`. See [Results](../core-language/errors/results.md).

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
- Test files run at once, each in its own promise, in one process; a file's tests run in order and share its fixture. Process-wide state (working directory, environment, files, services) is shared, so a test that changes it restores it. A fault in a test ends its file: later tests in that file are reported not run. `--shuffle` takes a seed.
- `--fail-fast` leaves remaining tests `not_run` in JSON.

## Property tests and fuzzing

A property test checks a rule on many generated inputs instead of a few hand-picked ones. `check` in `@std/test/property.ms` takes a name, a generator, and a function that returns a `Result` like any assertion. It runs 100 cases by default.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import check, ints, lists from "@std/test/property.ms"
import expect_equal from "@std/test/test.ms"

test "reversing twice restores a list":
    check("reverse twice", lists(ints(-100, 100)), fn xs: expect_equal(xs.reversed().reversed(), xs))?
```

Test output:

```text
RUN test.ms::reversing twice restores a list
PASS test.ms::reversing twice restores a list
1 tests, 0 failed
```

When a case fails, `check` shrinks the input to a small counterexample and fails the test with it and the case seed:

```text
FAIL test.ms::small sums: property 'small sums' failed after 3 cases (case seed 2039066943738375196; rerun with --seed 2039066943738375196)
counterexample: [50]
expected true, got false
```

- Generators: `ints(low, high)`, `bools()`, `floats(low, high)`, `strings(alphabet, max_length)`, `lists(gen, min_length, max_length)`, `optionals(gen)`, `pairs(a, b)`, `element_of(values)`, `one_of(gens)`, and `constant(value)`.
- Combine them with the `Gen` methods `map`, `zip`, `flat_map`, and `filter`, as on lists: `ints(1, 9).map(fn n: n * 2)`. A `filter` that cannot find a kept value discards the case; too many discards fail the test.
- Shrinking is automatic for every generator, including your own compositions: generators draw from a recorded stream of integers and shrinking edits and replays it. Integers shrink toward 0, lists toward fewer elements, `optionals` toward `none`, `bools` toward `false`.
- A generator value moves into the generator that uses it, so build a fresh `ints(...)` for each use rather than reusing one binding.
- A `panic` inside a property counts as a failing case and shrinks like a returned error; each case runs under `expect_fault`.

`ms test` controls property runs from the command line:

```sh
ms test ms.toml --runs 1000          # cases per property
ms test ms.toml --seed 2039066943738375196   # replay a reported failure
ms test ms.toml --fuzz 30s           # keep generating fresh cases for 30s per property
```

`--fuzz` replaces the case count with a time budget for each `check` call and prints the starting seed to standard error, so a fault that kills the process can still be replayed with `--seed`. It disables the default 60s `--timeout` unless you pass one. An explicit `seed:` argument to `check` overrides `--seed`. The [property-testing example](https://github.com/manuscript-lang/manuscript/tree/main/examples/property-testing) shows a project with several properties.

All assertions return `Result`, so use `?`:

- `expect_some`, `expect_ok`, `expect_error` yield the checked payload.
- `expect_fault(operation)` checks programming faults.
- `fail(message)?` fails explicitly; `skip(reason)?` skips the test.
- Write each independently reported case as its own `test` block.

## Golden files and misbehaving streams

`expect_golden(path, actual)` in `@std/test/golden.ms` compares text with a file kept next to the test and names the first differing line on a mismatch. Run `MS_UPDATE_GOLDEN=1 ms test ...` to rewrite the files from the actual output, review the change in version control, then run again without it. `expect_golden_bytes` does the same for bytes.

`@std/test/iotest.ms` wraps streams to test code that reads and writes: `one_byte(input)` trickles one byte per read, `fail_after(input, n, cause)` fails every read after `n` bytes, and `fail_writer_after(output, n, cause)` fails like a full disk. `check_reader(make, expected)` checks a `ReadStream` you wrote: whole reads, one-byte reads, a respected chunk size, and an end of input that stays ended.

## Benchmark your code

A `bench "name":` block works like a `test` block, but `ms bench` times it instead of checking it. The body is one iteration; `ms bench` repeats it until a sample takes about 100ms (that calibration is also the warmup), takes ten samples, and reports the time per iteration. `ms test` skips bench blocks. Save this complete file as `bench.ms`:

<!-- manuscript-example: {"mode":"bench"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn sum_to(n: Int) Int:
    var total = 0
    for i in 0..n:
        total += i
    return total

bench "sum to one hundred":
    expect_equal(sum_to(100), 4950)?
```

```sh
ms bench bench.ms
ms bench bench.ms --time 500ms --samples 20
ms bench ms.toml --filter "sum" --json
```

- A project loads `bench.ms` and `*_bench.ms` files; a bench may also sit in any module the command loads. Benches take the same selection options as tests (`--filter`, `--match`, `--exclude`, `--bench`, `--list`, `--repeat`, `--fail-fast`, `--timeout`).
- `--time` sets the target length of one sample, `--samples` the number of timed samples, and `--iterations` fixes the iteration count and skips calibration.
- `bench "name" per 1000:` declares that one iteration performs 1000 operations (a loop over 1000 items, say); every statistic is then per operation. `keep(value)` from `@std/test/bench.ms` checks a computed `Int` so the work stays observable.
- To keep setup out of the timing, build the data first and time only the work: `measure(1000, fn: keep(data.sorted().length()))?` from `@std/test/bench.ms` runs the work repeatedly and reports per operation, here for 1000 operations per run. Everything before `measure` runs once, untimed.
- Each bench runs in its own process. A body that returns an error, faults, or exceeds `--timeout` (default 10 minutes) fails that bench and the exit status is 1. Standard output written by a bench is discarded.
- `--json` adds `stats` to each entry of `benches`: `iterations`, `operations`, `samples`, and `min_ns`, `median_ns`, `mean_ns`, `max_ns`, `stddev_ns` in nanoseconds per operation (per iteration when `operations` is 1).
- Keep the measured work in the body and the setup outside it: a bench has no `fixture` and no hooks. Check a result with `?` so the compiler cannot discard the work; benchmark the default `Release` build.

## Profile application work

Use `ms profile` on a runnable project with an exported `main`:

```sh
ms profile ms.toml --out-dir capture --top 10
```

This runs the application entry point, not its test blocks. Put the workload you want to measure in the application's execution path. `capture` must be a new directory; the sampling profile includes folded stacks, pprof data, and a text report. The default build type is `Release`. See [profiling and native debugging](../developer-tooling/debugging/debugger-integration.md) for output files and source-attribution limits.

## Shared setup and teardown

Without `make_fixture`, no hooks run. Define `fn make_fixture() T` for a record or enum `T` and give it any of the hook methods `before_all`, `before_each`, `after_each` and `after_all`; tests then read it as `fixture`.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

type Counter:
    count: Int

fn make_fixture() Counter:
    return Counter(0)

fn var Counter.before_each() Unit!:
    self.count = 0

test "increments":
    fixture.count += 1
    expect_equal(fixture.count, 1)?

test "starts fresh":
    expect_equal(fixture.count, 0)?
```

Test output:

```text
RUN test.ms::increments
PASS test.ms::increments
RUN test.ms::starts fresh
PASS test.ms::starts fresh
2 tests, 0 failed
```

A file's tests share one fixture: `make_fixture` and `before_all` run once before the file's first test, `before_each` and `after_each` around each test, and `after_all` after the last, so `before_each` above resets the `Counter` that the second test reads. Each `--repeat` round runs the file again on a new fixture.

- One instance per file and run; a fault in a test still runs `after_each` and `after_all`, and the file's later tests are reported not run.
- Optional hooks (use `self`, no arguments, return `Unit!`): `before_all`, `before_each`, `after_each`, `after_all`. A hook's error fails the tests it guards; `skip(reason)?` skips them.
- Build in `make_fixture`, reset in `before_each`, release in `after_all`.

## Run tests only on some platforms

There is no platform attribute on `test` blocks. Skip at run time instead, comparing `os()` from `@std/os/system.ms` with an `Os` case (`Os.Linux`, `Os.Macos`, `Os.Windows`, or `Os.Other`). The file must still compile on every platform.

To skip a single test, call `skip` in its body:

```manuscript
import skip from "@std/test/test.ms"
import os, Os from "@std/os/system.ms"

test "unix permission bits":
    if os() == Os.Windows:
        skip("Unix only")?
    // Unix-only assertions follow.
```

To skip every test in a file, call `skip` from a fixture hook. `before_all` and `before_each` both work; `after_all` and `after_each` still run, and each test is reported as `SKIP` with your reason:

```manuscript
import skip from "@std/test/test.ms"
import os, Os from "@std/os/system.ms"

type WindowsOnly:
    ok: Bool

fn make_fixture() WindowsOnly:
    return WindowsOnly(os() == Os.Windows)

fn var WindowsOnly.before_all() Unit!:
    if not self.ok:
        skip("Windows only")?
```

Skipped tests are counted in the `ms test` summary, so a platform that runs nothing stays visible.
