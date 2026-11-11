import (
	Promise, promise, wait_all from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	float from "@std/random.ms",
	Duration, Instant, milliseconds, monotonic, seconds, sleep from "@std/time.ms",
)

/*
How `retry` spaces and bounds its attempts. The wait before attempt `n + 1` is `delay` doubled `n - 1` times, never more than `max_delay`;
with `jitter` the wait is a random share of that, so many callers do not retry in step.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
policy := RetryPolicy(attempts: 5, delay: milliseconds(50))
body := retry(policy, fn attempt: fetch(url).wait())
```
*/
export type RetryPolicy:
	// Total tries, including the first; at least 1.
	attempts: Int = 3
	// Wait before the second attempt.
	delay: Duration = milliseconds(100)
	// Upper bound of any wait.
	max_delay: Duration = seconds(30)
	// Whether each wait is a random share (0 to 1) of its computed length.
	jitter: Bool = true

impl RetryPolicy:
	// The wait after failed attempt number `attempt` (1 for the first), before jitter.
	fn wait_after(attempt: Int) Duration:
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
`operation` receives the attempt number, starting at 1. `E` must be `Clonable`, because the error is lent to `retryable` and then returned. `retryable` defaults to retrying every error.
Waiting uses `sleep`, so cancelling the task ends the wait. A policy with fewer than one attempt faults.
*/
export fn retry[T, E: Clonable](
	policy: RetryPolicy,
	operation: fn(Int) T!E,
	retryable: (fn(E) Bool)? = none
) T!E:
	if policy.attempts < 1:
		panic("retry: attempts must be at least 1, found {policy.attempts}")

	var attempt = 1

	while true:
		result := operation(attempt)
		if attempt >= policy.attempts: return result

		if result.is_error():
			if accepts := retryable:
				if not accepts(result.err()): return result
			sleep(jittered(policy, attempt)).wait().get(unit)
			attempt += 1
		else:
			return result

fn jittered(policy: RetryPolicy, attempt: Int) Duration:
	wait := policy.wait_after(attempt)
	if not policy.jitter: return wait

	share := float().get(1.0)
	return Duration(nanos: (wait.nanos.to_float() * share).truncate_to_int().get(0))

/*
A token bucket: holds up to `burst` tokens and gains one every `interval`. Each use of the limited resource takes a token.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
var limiter = rate_limiter(10, burst: 20)
for url in urls:
    limiter.acquire()
    _ := try fetch(url).wait()
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

impl RateLimiter:
	// Adds the tokens earned since the last refill.
	var fn refill() Unit:
		now := monotonic()
		earned := now.difference(self.stamp).nanos / self.interval.nanos.max(1)
		if earned <= 0: return unit

		// Compare with remaining room before adding: a valid large burst can overflow
		// the sum.
		if earned >= self.burst - self.tokens:
			self.tokens = self.burst
			self.stamp = now
		else:
			self.tokens += earned
			self.stamp = self.stamp.shift(self.interval.multiply(earned))

	// Takes a token if one is available and reports whether it did. Never waits.
	var fn try_acquire() Bool:
		self.refill()
		if self.tokens < 1: return false

		self.tokens -= 1
		return true

	// Waits until a token is available, then takes it. The wait ends when the task is
	// cancelled.
	var fn acquire() Unit:
		while not self.try_acquire():
			ready := self.stamp.shift(self.interval)
			sleep(ready.difference(monotonic()).max(Duration(nanos: 1))).wait().get(
				unit
			)

// A rate limiter that allows `count` uses per second with room for `burst` at once; it
// starts full. `count` and `burst` must be at least 1.
export fn rate_limiter(count: Int, burst: Int) RateLimiter:
	if count < 1 or burst < 1:
		panic(
			"rate_limiter: count and burst must be at least 1, found {count} and {burst}"
		)
	return RateLimiter(
		burst: burst,
		interval: seconds(1).divide(count),
		tokens: burst,
		stamp: monotonic(),
	)

// Why a circuit breaker call produced no result.
export enum CircuitError[E]:
	// The circuit is open: the call was not made.
	Open
	// The call ran and failed with this error.
	Failed(
		// The error the call returned.
		error: E
	)

/*
Stops calling something that keeps failing. After `threshold` failures in a row the circuit opens and calls fail at once with `Open`;
after `cooldown` one call is let through, and its result closes the circuit (success) or opens it again (failure).

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
var breaker = CircuitBreaker(threshold: 5, cooldown: seconds(10))
reply := breaker.call(fn: send(request))
```
*/
export type CircuitBreaker:
	// Consecutive failures that open the circuit; at least 1.
	threshold: Int
	// How long the circuit stays open before a trial call.
	cooldown: Duration
	// Internal state: the current run of failures.
	failures: Int = 0
	// Internal state: when the circuit opened, or `none` while closed.
	opened: Instant? = none

impl CircuitBreaker:
	// Whether a call may go ahead now: the circuit is closed, or its cooldown has
	// passed (the trial call).
	fn is_open() Bool:
		if since := self.opened:
			return monotonic().difference(since).compare(self.cooldown) < 0
		return false

	// Runs `operation` unless the circuit is open, and records the outcome.
	var fn call[T: Clonable, E: Clonable](operation: fn() T!E) T!CircuitError[E]:
		if self.is_open(): return error(CircuitError.Open)

		result := operation()

		if value := result:
			self.failures = 0
			self.opened = none
			return ok(value.clone())

		self.failures += 1
		if self.failures >= self.threshold or self.opened.is_some():
			self.opened = monotonic()
		return error(CircuitError.Failed(result.err().clone()))

// Applies `work` to every item with at most `limit` running at once and returns the
// results in the order of `items`. A failed worker promise cancels the others. If
// `work` returns a Result, that Result is an item in the returned list; inspect each
// outcome.
//
// <!-- manuscript-example: {"mode":"fragment"} -->
// ```manuscript
// doubled := try map_concurrent([1, 2, 3], 2, fn n: n * 2)  // [2, 4, 6]
// ```
export fn map_concurrent[T, U](items: List[T], limit: Int, work: fn(T) U) List[U]!:
	if limit < 1:
		panic("map_concurrent: limit must be at least 1, found {limit}")

	stripes := limit.min(items.length())
	var running: List[Promise[List[U]]] = []
	for stripe in 0..stripes:
		running.append(promise(fn: stripe_results(items, stripe, stripes, work)))

	var parts = try wait_all(running)
	var results: List[U] = []
	var index = items.length()

	while index > 0:
		index -= 1
		if value := parts[index % stripes].pop():
			results.append(value)

	results.reverse()
	return ok(results)

// The results of `work` for the items at `first`, `first + step`, and so on.
fn stripe_results[T, U](items: List[T], first: Int, step: Int, work: fn(T) U) List[U]!:
	var out: List[U] = []
	var index = first

	while index < items.length():
		out.append(work(items[index]))
		index += step

	return ok(out)

/*
A minimum spacing between actions: at most one per `interval`, the first one at once. Use it to throttle a stream of events.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
var spacing = Throttle(interval: milliseconds(200))
for event in events:
    if spacing.allow():
        redraw(event)
```
*/
export type Throttle:
	// The least time between two allowed actions.
	interval: Duration
	// Internal state: when the last action was allowed, or `none` before the first.
	last: Instant? = none

impl Throttle:
	// Reports whether an action may happen now, and if so counts it. Never waits.
	var fn allow() Bool:
		now := monotonic()
		if previous := self.last:
			if now.difference(previous).compare(self.interval) < 0: return false
		self.last = now
		return true

	// Waits until an action may happen, then counts it. The wait ends when the task is
	// cancelled.
	var fn wait() Unit:
		if previous := self.last:
			remaining := self.interval.subtract(monotonic().difference(previous))
			if remaining.nanos > 0:
				sleep(remaining).wait().get(unit)

		self.last = monotonic()
