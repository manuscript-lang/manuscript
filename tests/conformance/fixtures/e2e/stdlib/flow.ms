// conform: tags=testing,tier-io
// conform: phase=test
import (
	CircuitBreaker,
	CircuitError,
	RateLimiter,
	RetryPolicy,
	Throttle,
	map_concurrent,
	rate_limiter,
	retry from "@std/concurrency/flow.ms",
	expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms",
	Duration, milliseconds, monotonic, sleep from "@std/time.ms",
)

fn flaky(attempt: Int) Int!String:
	if attempt < 3: return error("try again")
	return ok(attempt)

fn never_retry(failure: String) Bool:
	return false

test "retry succeeds after failures":
	policy := RetryPolicy(attempts: 5, delay: milliseconds(1), jitter: false)
	value := expect_ok(retry(policy, flaky))?
	expect_equal(value, 3)?

test "retry gives up after the last attempt":
	policy := RetryPolicy(attempts: 2, delay: milliseconds(1))
	failure := expect_error(retry(policy, flaky))?
	expect_equal(failure, "try again")?

test "retry stops when the error is not retryable":
	policy := RetryPolicy(attempts: 5, delay: milliseconds(1))
	result := retry(policy, fn n: flaky(n), never_retry)
	failure := expect_error(result)?
	expect_equal(failure, "try again")?

test "backoff doubles and is capped":
	policy := RetryPolicy(delay: milliseconds(10), max_delay: milliseconds(50))
	expect_equal(policy.wait_after(1).nanos, milliseconds(10).nanos)?
	expect_equal(policy.wait_after(3).nanos, milliseconds(40).nanos)?
	expect_equal(policy.wait_after(9).nanos, milliseconds(50).nanos)?

test "backoff caps at a representable limit without overflowing":
	cap := 6000000000000000000
	policy := RetryPolicy(
		delay: Duration(nanos: 5000000000000000000),
		max_delay: Duration(nanos: cap),
		jitter: false,
	)
	expect_equal(policy.wait_after(1).nanos, 5000000000000000000)?
	expect_equal(policy.wait_after(2).nanos, cap)?
	expect_equal(policy.wait_after(40).nanos, cap)?

test "backoff reaching the cap exactly returns it":
	policy := RetryPolicy(delay: milliseconds(25), max_delay: milliseconds(50))
	expect_equal(policy.wait_after(2).nanos, milliseconds(50).nanos)?
	expect_equal(policy.wait_after(3).nanos, milliseconds(50).nanos)?

test "rate limiter allows a burst then waits":
	var limiter = rate_limiter(100, burst: 3)
	expect_true(limiter.try_acquire())?
	expect_true(limiter.try_acquire())?
	expect_true(limiter.try_acquire())?
	expect_true(not limiter.try_acquire())?

	start := monotonic()
	limiter.acquire()
	expect_true(monotonic().difference(start).nanos >= milliseconds(5).nanos)?

test "rate limiter refills a full maximum burst without overflowing":
	var limiter = rate_limiter(1, burst: 9223372036854775807)
	limiter.stamp = limiter.stamp.unshift(Duration(nanos: 1000000000))
	expect_true(limiter.try_acquire())?
	expect_equal(limiter.tokens, 9223372036854775807 - 1)?

test "rate limiter clamps an almost full maximum burst":
	var limiter = RateLimiter(
		burst: 9223372036854775807,
		tokens: 9223372036854775807 - 1,
		interval: Duration(nanos: 1),
		stamp: monotonic().unshift(Duration(nanos: 1000)),
	)
	expect_true(limiter.try_acquire())?
	expect_equal(limiter.tokens, 9223372036854775807 - 1)?

test "rate limiter refills an empty bucket only up to its burst":
	var limiter = RateLimiter(
		burst: 3,
		tokens: 0,
		interval: Duration(nanos: 1),
		stamp: monotonic().unshift(Duration(nanos: 1000)),
	)
	expect_true(limiter.try_acquire())?
	expect_equal(limiter.tokens, 2)?

fn boom() Int!String:
	return error("down")

fn fine() Int!String:
	return ok(1)

test "circuit opens after threshold and recovers after cooldown":
	var breaker = CircuitBreaker(threshold: 2, cooldown: milliseconds(20))
	_first := expect_error(breaker.call(boom))?
	_second := expect_error(breaker.call(boom))?
	third := expect_error(breaker.call(fine))?
	expect_equal(third, CircuitError[String].Open)?

	_ := sleep(milliseconds(30)).wait()
	value := expect_ok(breaker.call(fine))?
	expect_equal(value, 1)?

test "map_concurrent keeps order and respects the limit":
	doubled := expect_ok(map_concurrent([1, 2, 3, 4, 5], 2, fn n: n * 2))?
	expect_equal(doubled, [2, 4, 6, 8, 10])?

	none_left := expect_ok(map_concurrent(List[Int](), 3, fn n: n))?
	expect_equal(none_left.length(), 0)?

test "throttle allows one action per interval":
	var spacing = Throttle(interval: milliseconds(20))
	expect_true(spacing.allow())?
	expect_true(not spacing.allow())?

	_ := sleep(milliseconds(30)).wait()
	expect_true(spacing.allow())?

	start := monotonic()
	spacing.wait()
	expect_true(monotonic().difference(start).nanos >= milliseconds(10).nanos)?
