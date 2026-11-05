+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

Small types, explicit ownership and an offline code map help you review agent-written programs; Manuscript is in alpha, and syntax and APIs may change.

## Read the code, ship the executable {#familiar-to-read-native-to-run}

<!-- manuscript-example: {"mode":"test","filename":"review.ms","stdout":"RUN review.ms::copies stay independent\nPASS review.ms::copies stay independent\n1 tests, 0 failed\n"} -->
```manuscript {filename="review.ms"}
import expect_equal from "@std/test/test.ms"

fn identity[T](value: T) T:
    return value

test "copies stay independent":
    let original = [identity(3)]
    var edited = original.clone()
    edited.append(4)
    try expect_equal(original.length(), 1)
    try expect_equal(edited.length(), 2)
```

```sh
ms test review.ms
```

```text
RUN review.ms::copies stay independent
PASS review.ms::copies stay independent
1 tests, 0 failed
```

- A small type system with generics has no `any` escape hatch or runtime reflection API; interface contracts stay compiler-checked.
- `var` marks mutation and `.clone()` marks a copy; [native executables](../developer-tooling/how-it-works.md) run without `ms`.

## Understand what your agent built

```sh
ms diagram review.ms --format html -o code-map.html
```

- Succeeds silently; open `code-map.html` to follow source, checked types and calls offline.
- The map shows static relationships; [tests](testing.md) and [profiling](../developer-tooling/debugging/debugger-integration.md) investigate execution.

## Start concurrent work {#concurrency-without-async}

<!-- manuscript-example: {"mode":"test","filename":"work.ms","stdout":"RUN work.ms::collect concurrent work\nPASS work.ms::collect concurrent work\n1 tests, 0 failed\n"} -->
```manuscript {filename="work.ms"}
import promise from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

test "collect concurrent work":
    let answer = promise[Int](fn: ok(6 * 7))
    try expect_equal(try answer.wait(), 42)
```

```sh
ms test work.ms
```

```text
RUN work.ms::collect concurrent work
PASS work.ms::collect concurrent work
1 tests, 0 failed
```

- `promise` starts work eagerly; `wait` returns its result.
- Dropping unfinished work cancels and waits; [cancellation is cooperative](../core-language/concurrency/promises.md#cancellation).

## Batteries-included standard library {#a-growing-standard-library}

<!-- manuscript-example: {"mode":"test","filename":"config.ms","stdout":"RUN config.ms::configuration defaults\nPASS config.ms::configuration defaults\n1 tests, 0 failed\n"} -->
```manuscript {filename="config.ms"}
import parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

type Config:
    port: Int = 8080

test "configuration defaults":
    let config = try parse[Config]("\{\}")
    try expect_equal(config.port, 8080)
```

```sh
ms test config.ms
```

```text
RUN config.ms::configuration defaults
PASS config.ms::configuration defaults
1 tests, 0 failed
```

- Files, HTTP, streams, JSON, time, crypto and testing APIs ship with `ms`; try the [recipes](common-tasks.md).
- `try` forwards expected errors; the declared shape controls typed JSON decoding.

<span id="feedback-an-agent-can-act-on"></span>
<span id="ownership-you-can-follow"></span>
<span id="measured-against-agents"></span>
<span id="where-this-is-going"></span>
<span id="try-it"></span>

Next: [first program](getting-started.md), [agent commands](../developer-tooling/implementation.md#commands-for-agents), [concurrency](../core-language/concurrency/_index.md), [ownership](../core-language/types/references.md), [measured results](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md).
