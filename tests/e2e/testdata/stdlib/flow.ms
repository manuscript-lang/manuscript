import (
    RetryPolicy,
    retry,
    rate_limiter,
    CircuitBreaker,
    CircuitError,
    map_concurrent,
    Throttle
) from "@std/concurrency/flow.ms"
import expect_equal, expect_true, expect_error, expect_ok from "@std/test/test.ms"
import milliseconds, sleep, monotonic from "@std/time.ms"

fn flaky(attempt: Int) Int!String:
    if attempt < 3:
        return error("try again")

    return ok(attempt)

fn never_retry(failure: String) Bool:
    return false

test "retry succeeds after failures":
    let policy = RetryPolicy(attempts: 5, delay: milliseconds(1), jitter: false)
    let value = try expect_ok(retry(policy, flaky))
    try expect_equal(value, 3)

test "retry gives up after the last attempt":
    let policy = RetryPolicy(attempts: 2, delay: milliseconds(1))
    let failure = try expect_error(retry(policy, flaky))
    try expect_equal(failure, "try again")

test "retry stops when the error is not retryable":
    let policy = RetryPolicy(attempts: 5, delay: milliseconds(1))
    let result = retry(policy, fn n: flaky(n), never_retry)
    let failure = try expect_error(result)
    try expect_equal(failure, "try again")

test "backoff doubles and is capped":
    let policy = RetryPolicy(delay: milliseconds(10), max_delay: milliseconds(50))
    try expect_equal(policy.wait_after(1).nanos, milliseconds(10).nanos)
    try expect_equal(policy.wait_after(3).nanos, milliseconds(40).nanos)
    try expect_equal(policy.wait_after(9).nanos, milliseconds(50).nanos)

test "rate limiter allows a burst then waits":
    var limiter = rate_limiter(100, burst: 3)
    try expect_true(limiter.try_acquire())
    try expect_true(limiter.try_acquire())
    try expect_true(limiter.try_acquire())
    try expect_true(not limiter.try_acquire())

    let start = monotonic()
    limiter.acquire()
    try expect_true(monotonic().difference(start).nanos >= milliseconds(5).nanos)

fn boom() Int!String:
    return error("down")

fn fine() Int!String:
    return ok(1)

test "circuit opens after threshold and recovers after cooldown":
    var breaker = CircuitBreaker(threshold: 2, cooldown: milliseconds(20))
    let _first = try expect_error(breaker.call(boom))
    let _second = try expect_error(breaker.call(boom))
    let third = try expect_error(breaker.call(fine))
    try expect_equal(third, CircuitError[String].Open)

    let _ = sleep(milliseconds(30)).wait()
    let value = try expect_ok(breaker.call(fine))
    try expect_equal(value, 1)

test "map_concurrent keeps order and respects the limit":
    let doubled = try expect_ok(map_concurrent([1, 2, 3, 4, 5], 2, fn n: n * 2))
    try expect_equal(doubled, [2, 4, 6, 8, 10])

    let none_left = try expect_ok(map_concurrent(List[Int](), 3, fn n: n))
    try expect_equal(none_left.length(), 0)

test "throttle allows one action per interval":
    var spacing = Throttle(interval: milliseconds(20))
    try expect_true(spacing.allow())
    try expect_true(not spacing.allow())

    let _ = sleep(milliseconds(30)).wait()
    try expect_true(spacing.allow())

    let start = monotonic()
    spacing.wait()
    try expect_true(monotonic().difference(start).nanos >= milliseconds(10).nanos)
