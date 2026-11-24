+++
title = "Retries and limits"
weight = 18
+++

# Retries and limits

Call something that can fail, retry with growing waits, and stop calling it when it keeps failing.

## Retry with backoff

Save as `retry.ms`. `retry` calls the operation with the attempt number until it succeeds or the attempts run out. The wait doubles after each failure, up to `max_delay`. The optional third argument says which errors are worth retrying.

<!-- manuscript-example: {"mode":"run","stdout":"attempt 1\nattempt 2\nattempt 3\nsucceeded after 3 attempts\n"} -->
```manuscript
import RetryPolicy, retry from "@std/concurrency/resilience.ms"
import milliseconds from "@std/time.ms"

fn flaky(attempt Int) Int!:
    print(f"attempt {attempt}")
    if attempt < 3:
        return error(Error("temporarily unavailable", kind: "EAGAIN"))
    return ok(attempt)

fn main() Void!:
    policy := RetryPolicy(attempts: 5, delay: milliseconds(10), jitter: false)
    attempts := retry(policy, flaky)?
    print(f"succeeded after {attempts} attempts")
```

```sh
ms run retry.ms
```

- Only retry errors that can go away. Pass a function such as `e => e.kind == "EAGAIN"` as the third argument to retry those and return the rest at once.
- Keep `jitter` on in services, so many callers that failed together do not retry together.
- Waiting uses `sleep`, so cancelling the task ends the wait.

## Stop calling a failing dependency

Save as `breaker.ms`. After `threshold` failures in a row the circuit opens, and calls fail at once with `Open` instead of waiting on a dependency that is down. After `cooldown`, one call is let through to test it.

<!-- manuscript-example: {"mode":"run","stdout":"failed: down\nfailed: down\nopen: call skipped\n"} -->
```manuscript
import CircuitBreaker, CircuitError from "@std/concurrency/resilience.ms"
import seconds from "@std/time.ms"

fn down() Int!:
    return error(Error("down", kind: "ECONNREFUSED"))

fn main() Void:
    var breaker = CircuitBreaker(threshold: 2, cooldown: seconds(30))
    for round in 0..3:
        result := breaker.call(down)
        match result.err():
            Failed(cause) => print(f"failed: {cause.message}")
            Open => print("open: call skipped")
```
