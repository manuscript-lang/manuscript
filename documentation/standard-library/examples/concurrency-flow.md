+++
title = "Control concurrent work"
+++

# Control concurrent work

Review retry bounds, rate limits, circuit failures, and concurrent result collection. APIs may evolve during alpha.

## Bound retry attempts

<!-- manuscript-example: {"mode":"test","filename":"retry-attempts.ms","stdout":"RUN retry-attempts.ms::retry-attempts\nPASS retry-attempts.ms::retry-attempts\n1 tests, 0 failed\n"} -->
```manuscript {filename="retry-attempts.ms"}
import RetryPolicy, retry from "@std/concurrency/flow.ms"
import milliseconds from "@std/os/time.ms"
import expect_equal from "@std/test/test.ms"

fn attempt_value(attempt: Int) Int!:
    if attempt == 1:
        return error(Error("try again"))
    return ok(attempt)

test "retry-attempts":
    let policy = RetryPolicy(attempts: 2, delay: milliseconds(0), jitter: false)
    let result = try retry(policy, fn attempt: attempt_value(attempt))
    try expect_equal(result, 2)
```

```sh
ms test retry-attempts.ms
```

```text
RUN retry-attempts.ms::retry-attempts
PASS retry-attempts.ms::retry-attempts
1 tests, 0 failed
```

## Pace a sequence of requests

<!-- manuscript-example: {"mode":"run","filename":"rate-limit.ms","stdout":"Ada\nSam\n"} -->
```manuscript {filename="rate-limit.ms"}
import rate_limiter from "@std/concurrency/flow.ms"

export fn main() Int:
    var limiter = rate_limiter(10, burst: 2)
    for name in ["Ada", "Sam"]:
        limiter.acquire()
        print(name)
    return 0
```

```sh
ms run rate-limit.ms
```

```text
Ada
Sam
```

## Handle an open circuit

<!-- manuscript-example: {"mode":"test","filename":"circuit-breaker.ms","stdout":"RUN circuit-breaker.ms::circuit-breaker\nPASS circuit-breaker.ms::circuit-breaker\n1 tests, 0 failed\n"} -->
```manuscript {filename="circuit-breaker.ms"}
import CircuitBreaker, CircuitError from "@std/concurrency/flow.ms"
import seconds from "@std/os/time.ms"
import expect_equal from "@std/test/test.ms"

test "circuit-breaker":
    var breaker = CircuitBreaker(threshold: 1, cooldown: seconds(60))
    let failed: Int! = error(Error("service unavailable"))
    let outcome = breaker.call(fn: failed.clone())
    match outcome:
        ok(_): return error(Error("expected the service failure"))
        error(cause):
            try expect_equal(cause, CircuitError[Error].Failed(Error("service unavailable")))
    try expect_equal(breaker.is_open(), true)
```

```sh
ms test circuit-breaker.ms
```

```text
RUN circuit-breaker.ms::circuit-breaker
PASS circuit-breaker.ms::circuit-breaker
1 tests, 0 failed
```

## Collect concurrent results

<!-- manuscript-example: {"mode":"test","filename":"parallel-map.ms","stdout":"RUN parallel-map.ms::parallel-map\nPASS parallel-map.ms::parallel-map\n1 tests, 0 failed\n"} -->
```manuscript {filename="parallel-map.ms"}
import map_concurrent from "@std/concurrency/flow.ms"
import expect_equal from "@std/test/test.ms"

test "parallel-map":
    let doubled = try map_concurrent([1, 2, 3], 2, fn n: n * 2)
    try expect_equal(doubled, [2, 4, 6])
```

```sh
ms test parallel-map.ms
```

```text
RUN parallel-map.ms::parallel-map
PASS parallel-map.ms::parallel-map
1 tests, 0 failed
```

## Throttle a stream

<!-- manuscript-example: {"mode":"run","filename":"throttle.ms","stdout":"Ada\nSam\n"} -->
```manuscript {filename="throttle.ms"}
import Throttle from "@std/concurrency/flow.ms"
import milliseconds from "@std/os/time.ms"

export fn main() Int:
    var spacing = Throttle(interval: milliseconds(1))
    for name in ["Ada", "Sam"]:
        spacing.wait()
        print(name)
    return 0
```

```sh
ms run throttle.ms
```

```text
Ada
Sam
```

See the [API reference](../reference/concurrency/flow.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
