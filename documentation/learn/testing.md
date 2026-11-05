+++
title = "Test your code"
weight = 3
+++

# Test your code

Tests turn an agent’s claims into outcomes you can review; save each example separately as `test.ms`. Manuscript is in alpha, and syntax and APIs may change.

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::addition\nPASS test.ms::addition\nRUN test.ms::zero is unchanged\nPASS test.ms::zero is unchanged\n2 tests, 0 failed\n"} -->
```manuscript {filename="test.ms"}
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

- Assertions return `T!`; `try` makes an assertion failure fail the test.
- Faults and timeouts also fail tests; each selected test runs in its own process.

## Select and repeat

List the opening example’s test names before selecting one.

```sh
ms test test.ms --list
```

```text
test.ms::addition
test.ms::zero is unchanged
```

```sh
ms test test.ms --test "test.ms::addition"
```

```text
RUN test.ms::addition
PASS test.ms::addition
1 tests, 0 failed
```

- `--filter` selects name substrings; `--repeat` repeats selected tests and `--shuffle` takes a seed.
- `--timeout` bounds each test (default 60s); `--json` produces structured results.

## Check payloads and errors

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::typed JSON accepts the expected shape\nPASS test.ms::typed JSON accepts the expected shape\n1 tests, 0 failed\n"} -->
```manuscript {filename="test.ms"}
import parse from "@std/data/json.ms"
import expect_equal, expect_error from "@std/test/test.ms"

test "typed JSON accepts the expected shape":
    let number = try parse[Int]("3")
    try expect_equal(number, 3)
    let cause = try expect_error(parse[Int]("true"))
    try expect_equal(cause.kind, "EBADMSG")
```

```sh
ms test test.ms
```

```text
RUN test.ms::typed JSON accepts the expected shape
PASS test.ms::typed JSON accepts the expected shape
1 tests, 0 failed
```

- Use `expect_error` to test an expected failure without discarding its cause.

## Property tests and fuzzing

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::reversing twice restores a list\nPASS test.ms::reversing twice restores a list\n1 tests, 0 failed\n"} -->
```manuscript {filename="test.ms"}
import check, ints, lists from "@std/test/property.ms"
import expect_equal from "@std/test/test.ms"

test "reversing twice restores a list":
    try check("reverse twice", lists(ints(-100, 100)), fn xs: expect_equal(xs.reversed().reversed(), xs))
```

```sh
ms test test.ms
```

```text
RUN test.ms::reversing twice restores a list
PASS test.ms::reversing twice restores a list
1 tests, 0 failed
```

- A property checks 100 generated cases by default and shrinks a failure to a smaller counterexample.
- `--runs` sets the count; `--seed` replays a reported seed; `--fuzz` sets a time budget per property.

## Golden files and misbehaving streams

Create `greeting.txt` containing `Hello!` and a newline before running this test.

<!-- manuscript-example: {"mode":"test","filename":"test.ms","files":{"greeting.txt":"Hello!\n"},"stdout":"RUN test.ms::greeting stays stable\nPASS test.ms::greeting stays stable\n1 tests, 0 failed\n"} -->
```manuscript {filename="test.ms"}
import expect_golden from "@std/test/golden.ms"

test "greeting stays stable":
    try expect_golden("greeting.txt", "Hello!\n")
```

```sh
ms test test.ms
```

```text
RUN test.ms::greeting stays stable
PASS test.ms::greeting stays stable
1 tests, 0 failed
```

- Review changed golden files before accepting new output.
- Use the [I/O test helpers](../standard-library/reference/test/iotest.ms.md) to exercise short reads and failed writes.

## Shared setup and teardown

<!-- manuscript-example: {"mode":"test","filename":"test.ms","stdout":"RUN test.ms::increments\nPASS test.ms::increments\nRUN test.ms::starts fresh\nPASS test.ms::starts fresh\n2 tests, 0 failed\n"} -->
```manuscript {filename="test.ms"}
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

```sh
ms test test.ms
```

```text
RUN test.ms::increments
PASS test.ms::increments
RUN test.ms::starts fresh
PASS test.ms::starts fresh
2 tests, 0 failed
```

- Each test creates a fresh fixture; external files and services still need their own reset.
- Release fixture resources in `after_all`; [test hooks](../standard-library/reference/test/test.ms.md) also support setup and per-test cleanup.

## Run tests in a project

- `ms test ms.toml` finds `test.ms` and `*_test.ms`; import application code with relative paths.
- Project tests use the manifest directory for relative paths; see [discovery rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-driver/src/project/discovery.rs).

## Benchmark your code

Save as `bench.ms`; the assertion keeps the computed result observable.

<!-- manuscript-example: {"mode":"bench","filename":"bench.ms","test_stdout":"RUN bench.ms::sum is correct\nPASS bench.ms::sum is correct\n1 tests, 0 failed\n"} -->
```manuscript {filename="bench.ms"}
import expect_equal from "@std/test/test.ms"

fn sum_to(n: Int) Int:
    var total = 0
    for i in 0..n:
        total += i
    return total

test "sum is correct":
    try expect_equal(sum_to(100), 4950)

bench "sum to one hundred":
    try expect_equal(sum_to(100), 4950)
```

```sh
ms test bench.ms
```

```text
RUN bench.ms::sum is correct
PASS bench.ms::sum is correct
1 tests, 0 failed
```

```sh
ms bench bench.ms
```

The timing report ends with this summary:

```text
1 benches, 0 failed
```

- Timings vary: the report shows median, minimum, mean, maximum and standard deviation in nanoseconds per operation.
- Defaults use ten samples of about 100ms each; use `measure` for [untimed setup](../standard-library/reference/test/bench.ms.md).

<span id="profile-application-work"></span>
<span id="run-tests-only-on-some-platforms"></span>

Next: [benchmark API](../standard-library/reference/test/bench.ms.md), [profiling](../developer-tooling/debugging/debugger-integration.md), [test skipping](../standard-library/reference/test/test.ms.md), [task recipes](common-tasks.md).
