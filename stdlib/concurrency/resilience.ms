// ms: allow_effect std.clock.read
// ms: allow_effect std.clock.sleep
// ms: allow_effect std.random.read

import (
	Promise, caller_frame, promise, wait_all from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	float from "@std/random.ms",
	Duration, Instant, milliseconds, monotonic, seconds, sleep from "@std/time.ms",
)

/*
How `retry` spaces and bounds its attempts. The wait before attempt `n + 1` is `delay` doubled `n - 1` times, never more than `max_delay`.
With `jitter`, the wait is a random share of that, so many callers do not retry in step.

<!-- manuscript-example: {"mode":"fragment","given":["url: String"]} -->
```manuscript
import RetryPolicy, retry from "@std/concurrency/resilience.ms"
import fetch from "@std/net/fetch.ms"
import milliseconds from "@std/time.ms"

policy := RetryPolicy(attempts: 5, delay: milliseconds(50))
body := retry(policy, fn attempt: fetch(url).wait())
if body.is_error(): print("gave up")
```
*/
export type RetryPolicy:
	// Total tries, including the first; at least 1.
	attempts: Int = 3
	// Wait before the second attempt.
	delay: Duration = milliseconds(100)
	// Upper bound on any wait.
	max_delay: Duration = seconds(30)
	// Whether each wait is a random share (0 to 1) of its computed length.
	jitter: Bool = true

// Internal: the wait after failed attempt number `attempt` (1 for the first), before
// jitter.
fn RetryPolicy.wait_after(attempt: Int) Duration:
	var wait = Duration(nanos: self.delay.nanos)

	for round in 1..attempt:
		if wait.compare(self.max_delay) >= 0: break

		// Doubling would reach the cap: stop before the product can overflow.
		if self.max_delay.nanos > 0 and wait.nanos > self.max_delay.nanos / 2:
			wait = Duration(nanos: self.max_delay.nanos)
			break

		wait = wait.multiply(2)

	return Duration(nanos: wait.nanos.min(self.max_delay.nanos))

/*
Runs `operation` until it succeeds, `retryable` rejects its error, or `policy.attempts` is used up, and returns the last result.
`operation` receives the attempt number, starting at 1. `retryable` defaults to retrying every error.
`E` must be `Clonable`, because `retryable` borrows the error and `retry` then returns it.
Waiting uses `sleep`, so cancelling the task ends the wait. The operation always runs once, so a policy with fewer than one attempt still runs it once.
*/
export fn retry[T, E: Clonable](
	policy: RetryPolicy,
	operation: fn(Int) T!E,
	retryable: (fn(E) Bool)? = null
) T!E:
	var attempt = 1

	while true:
		result := operation(attempt)
		if attempt >= policy.attempts: return result

		if result.is_error():
			accepts := retryable
			if accepts != null:
				if not accepts(result.err()): return result
			void sleep(jittered(policy, attempt)).wait()
			attempt += 1
		else:
			return result

fn jittered(policy: RetryPolicy, attempt: Int) Duration:
	wait := policy.wait_after(attempt)
	if not policy.jitter: return wait

	share := float().get_or(1.0)
	return Duration(nanos: (wait.nanos.to_float() * share).truncate_to_int() or 0)

/*
A token bucket: holds up to `burst` tokens and gains one every `interval`. Each use of the limited resource takes a token.

<!-- manuscript-example: {"mode":"fragment","given":["urls: List[String]"]} -->
```manuscript
import rate_limiter from "@std/concurrency/resilience.ms"
import fetch from "@std/net/fetch.ms"

var limiter = rate_limiter(10, burst: 20)?
for url in urls:
    limiter.acquire()
    void fetch(url).wait()?
```
*/
export type RateLimiter:
	// Most tokens held at once; at least 1.
	burst: Int
	// Time to gain one token.
	interval: Duration
	// Internal state: tokens available as of `stamp`.
	tokens: Int
	// Internal state: the reading up to which refills are counted.
	stamp: Instant

// Internal: adds the tokens earned since the last refill.
fn var RateLimiter.refill() Void:
	now := monotonic()
	earned := now.difference(self.stamp).nanos / self.interval.nanos.max(1)
	if earned <= 0: return

	// Compare with remaining room before adding: a valid large burst can overflow
	// the sum.
	if earned >= self.burst - self.tokens:
		self.tokens = self.burst
		self.stamp = now
	else:
		self.tokens += earned
		self.stamp = self.stamp.shift(self.interval.multiply(earned))

// Takes a token if one is available and reports whether it did. It never waits.
fn var RateLimiter.try_acquire() Bool:
	self.refill()
	if self.tokens < 1: return false

	self.tokens -= 1
	return true

// Waits until a token is available, then takes it. Cancelling the task ends the
// wait.
fn var RateLimiter.acquire() Void:
	while not self.try_acquire():
		ready := self.stamp.shift(self.interval)
		void sleep(ready.difference(monotonic()).max(Duration(nanos: 1))).wait()

// Returns a rate limiter that allows `count` uses per second, with room for `burst`
// uses at once. It starts full. A `count` or `burst` below 1 returns `EINVAL`.
export fn rate_limiter(count: Int, burst: Int) RateLimiter!:
	if count < 1 or burst < 1:
		return error(
			Error(
				f"rate_limiter: count and burst must be at least 1, found {count} and {burst}",
				kind: "EINVAL",
			)
		)
	return ok(
		RateLimiter(
			burst: burst,
			interval: seconds(1).divide(count),
			tokens: burst,
			stamp: monotonic(),
		)
	)

// Why a circuit breaker call produced no result: the circuit was open, or the call
// failed.
export enum CircuitError[E]:
	// The circuit is open: the call was not made.
	Open
	// The call ran and failed with this error.
	Failed(
		// The error the call returned.
		error: E
	)

/*
Stops calling something that keeps failing. After `threshold` failures in a row the circuit opens, and calls fail at once with `Open`.
After `cooldown`, one call is let through: success closes the circuit, and failure opens it again.

<!-- manuscript-example: {"mode":"fragment","given":["request: String"]} -->
```manuscript
import CircuitBreaker from "@std/concurrency/resilience.ms"
import fetch from "@std/net/fetch.ms"
import seconds from "@std/time.ms"

var breaker = CircuitBreaker(threshold: 5, cooldown: seconds(10))
reply := breaker.call(fn: fetch(request).wait())
if reply.is_error(): print("circuit open or call failed")
```
*/
export type CircuitBreaker:
	// Consecutive failures that open the circuit; at least 1.
	threshold: Int
	// How long the circuit stays open before a trial call.
	cooldown: Duration
	// Internal state: the current run of failures.
	failures: Int = 0
	// Internal state: when the circuit opened, or `null` while closed.
	opened: Instant? = null

// Reports whether the circuit is open and still cooling down, so a call fails at
// once. It is false while the circuit is closed, and once the cooldown has passed,
// which lets the trial call through.
fn CircuitBreaker.is_open() Bool:
	since := self.opened
	if since != null: return monotonic().difference(since).compare(self.cooldown) < 0

	return false

// Runs `operation` unless the circuit is open, and records the outcome. An open
// circuit returns `CircuitError.Open` without calling it; a failed call returns
// `CircuitError.Failed` with the error.
fn var CircuitBreaker.call[T: Clonable, E: Clonable](
	operation: fn() T!E
) T!CircuitError[E]:
	if self.is_open(): return error(CircuitError.Open)

	result := operation()

	if value := result:
		self.failures = 0
		self.opened = null
		return ok(value.clone())

	self.failures += 1
	if self.failures >= self.threshold or (self.opened != null):
		self.opened = monotonic()
	return error(CircuitError.Failed(result.err().clone()))

// Applies `work` to every item with at most `limit` running at once and returns the
// results in the order of `items`. A failed worker promise cancels the others. If
// `work` returns a Result, that Result is an item in the returned list; inspect each
// outcome. A `limit` below 1 is `EINVAL`.
//
// <!-- manuscript-example: {"mode":"fragment","given":[]} -->
// ```manuscript
// import map_concurrent from "@std/concurrency/resilience.ms"
//
// doubled := map_concurrent([1, 2, 3], 2, fn n: n * 2)?  // [2, 4, 6]
// print(doubled.length())
// ```
export fn map_concurrent[T, U](
	items: List[T],
	limit: Int,
	work: fn(T) U,
	site: String = caller_frame()
) List[U]!:
	if limit < 1:
		return error(
			Error(
				f"map_concurrent: limit must be at least 1, found {limit}",
				kind: "EINVAL",
			)
		)

	stripes := limit.min(items.length())
	var running: List[Promise[List[U]]] = []

	for stripe in 0..stripes:
		mine := items.clone()
		running.append(
			promise(
				fn: stripe_results(mine, stripe, stripes, work),
				site: site
			)
		)

	var parts = wait_all(running)?
	var results: List[U] = []
	var index = items.length()

	while index > 0:
		index -= 1

		value := parts[index % stripes].pop()
		if value != null:
			results.append(value)

	results.reverse()
	return ok(results)

// Internal: the results of `work` for the items at `first`, `first + step`, and so
// on.
fn stripe_results[T, U](items: List[T], first: Int, step: Int, work: fn(T) U) List[U]!:
	var out: List[U] = []
	var index = first

	while index < items.length():
		out.append(work(items[index]))
		index += step

	return ok(out)

/*
A minimum spacing between actions: at most one per `interval`, the first one at once. Use it to throttle a stream of events.

<!-- manuscript-example: {"mode":"fragment","given":["events: List[String]"]} -->
```manuscript
import Throttle from "@std/concurrency/resilience.ms"
import milliseconds from "@std/time.ms"

var spacing = Throttle(interval: milliseconds(200))
for event in events:
    if spacing.allow():
        print(event)
```
*/
export type Throttle:
	// The least time between two allowed actions.
	interval: Duration
	// Internal state: when the last action was allowed, or `null` before the first.
	last: Instant? = null

// Reports whether an action may happen now, and if so counts it. It never waits.
fn var Throttle.allow() Bool:
	now := monotonic()
	previous := self.last
	if previous != null:
		if now.difference(previous).compare(self.interval) < 0: return false
	self.last = now
	return true

// Waits until an action may happen, then counts it. Cancelling the task ends the
// wait.
fn var Throttle.wait() Void:
	previous := self.last

	if previous != null:
		remaining := self.interval.subtract(monotonic().difference(previous))
		if remaining.nanos > 0:
			void sleep(remaining).wait()

	self.last = monotonic()
