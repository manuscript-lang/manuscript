import panic from "@std/core.ms"
import Deque from "@std/collections/deque.ms"
import TaskError, TaskGroup from "@std/concurrency/tasks.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import Channel from "@std/io/channels.ms"
import Duration, Instant, milliseconds, monotonic, seconds, sleep from "@std/os/time.ms"
import float from "@std/os/random.ms"

# How `retry` spaces and bounds its attempts. The wait before attempt `n + 1` is `delay` doubled `n - 1` times, never more than `max_delay`;
# with `jitter` the wait is a random share of that, so many callers do not retry in step.
#
# ```manuscript
# let policy = RetryPolicy(attempts: 5, delay: milliseconds(50))
# let body = retry(policy, fn attempt: fetch(url))
# ```
export type RetryPolicy:
    # Total tries, including the first; at least 1.
    attempts: Int = 3
    # Wait before the second attempt.
    delay: Duration = milliseconds(100)
    # Upper bound of any wait.
    max_delay: Duration = seconds(30)
    # Whether each wait is a random share (0 to 1) of its computed length.
    jitter: Bool = true

impl RetryPolicy:
    # The wait after failed attempt number `attempt` (1 for the first), before jitter.
    fn wait_after(attempt: Int) Duration:
        var wait = Duration(nanos: self.delay.nanos)

        for round in 1..attempt:
            if wait.compare(self.max_delay) >= 0:
                break

            wait = wait.multiply(2)

        return Duration(nanos: wait.nanos.min(self.max_delay.nanos))

# Runs `operation` until it succeeds, `retryable` rejects its error, or `policy.attempts` is used up, and returns the last result.
# `operation` receives the attempt number, starting at 1. `retryable` defaults to retrying every error.
# Waiting uses `sleep`, so cancelling the task ends the wait. A policy with fewer than one attempt faults.
export fn retry[T, E](
    policy: RetryPolicy,
    operation: fn(Int) T!E,
    retryable: (fn(E) Bool)? = none
) T!E:
    if policy.attempts < 1:
        panic("retry: attempts must be at least 1, found {policy.attempts}")

    var attempt = 1

    while true:
        let result = operation(attempt)
        if attempt >= policy.attempts:
            return result

        if result.is_error():
            if let accepts = retryable:
                if not accepts(result.err()):
                    return result
            sleep(jittered(policy, attempt))
            attempt += 1
        else:
            return result

fn jittered(policy: RetryPolicy, attempt: Int) Duration:
    let wait = policy.wait_after(attempt)
    if not policy.jitter:
        return wait

    let share = float().get(1.0)
    return Duration(nanos: (wait.nanos.to_float() * share).truncate_to_int().get(0))

# A token bucket: holds up to `burst` tokens and gains one every `interval`. Each use of the limited resource takes a token.
#
# ```manuscript
# var limiter = rate_limiter(10, burst: 20)
# for url in urls:
#     limiter.acquire()
#     fetch(url)
# ```
export type RateLimiter:
    # Most tokens held at once; at least 1.
    burst: Int
    # Time to gain one token.
    interval: Duration
    # Internal state: tokens available as of `stamp`.
    tokens: Int
    # Internal state: the reading up to which refills are counted.
    stamp: Instant

# A rate limiter that allows `count` uses per second with room for `burst` at once; it starts full. `count` and `burst` must be at least 1.
export fn rate_limiter(count: Int, burst: Int) RateLimiter:
    if count < 1 or burst < 1:
        panic(
            "rate_limiter: count and burst must be at least 1, found {count} and {burst}"
        )
    return RateLimiter(
        burst: burst, interval: seconds(1).divide(count), tokens: burst,
        stamp: monotonic()
    )

impl RateLimiter:
    # Adds the tokens earned since the last refill.
    var fn refill() Unit:
        let now = monotonic()
        let earned = now.difference(self.stamp).nanos / self.interval.nanos.max(1)
        if earned <= 0:
            return unit

        if self.tokens + earned >= self.burst:
            self.tokens = self.burst
            self.stamp = now
        else:
            self.tokens += earned
            self.stamp = self.stamp.shift(self.interval.multiply(earned))

    # Takes a token if one is available and reports whether it did. Never waits.
    var fn try_acquire() Bool:
        self.refill()
        if self.tokens < 1:
            return false

        self.tokens -= 1
        return true

    # Waits until a token is available, then takes it. The wait ends when the task is cancelled.
    var fn acquire() Unit:
        while not self.try_acquire():
            let ready = self.stamp.shift(self.interval)
            sleep(ready.difference(monotonic()).max(Duration(nanos: 1)))

# Why a circuit breaker call produced no result.
export type CircuitError[E]:
    # The circuit is open: the call was not made.
    case Open
    # The call ran and failed with this error.
    case Failed(
        # The error the call returned.
        error: E
    )

# Stops calling something that keeps failing. After `threshold` failures in a row the circuit opens and calls fail at once with `Open`;
# after `cooldown` one call is let through, and its result closes the circuit (success) or opens it again (failure).
#
# ```manuscript
# var breaker = CircuitBreaker(threshold: 5, cooldown: seconds(10))
# let reply = breaker.call(fn: send(request))
# ```
export type CircuitBreaker:
    # Consecutive failures that open the circuit; at least 1.
    threshold: Int
    # How long the circuit stays open before a trial call.
    cooldown: Duration
    # Internal state: the current run of failures.
    failures: Int = 0
    # Internal state: when the circuit opened, or `none` while closed.
    opened: Instant? = none

impl CircuitBreaker:
    # Whether a call may go ahead now: the circuit is closed, or its cooldown has passed (the trial call).
    fn is_open() Bool:
        if let since = self.opened:
            return monotonic().difference(since).compare(self.cooldown) < 0

        return false

    # Runs `operation` unless the circuit is open, and records the outcome.
    var fn call[T: Clonable, E: Clonable](operation: fn() T!E) T!CircuitError[E]:
        if self.is_open():
            return error(CircuitError.Open)

        let result = operation()

        if let value = result:
            self.failures = 0
            self.opened = none
            return ok(value.clone())

        self.failures += 1
        if self.failures >= self.threshold or self.opened.is_some():
            self.opened = monotonic()
        return error(CircuitError.Failed(result.err().clone()))

# Applies `work` to every item with at most `limit` running at once and returns the results in the order of `items`.
# Items start in order; a worker takes the next as soon as it finishes one. Returns the task error if a worker is cancelled or timed out.
#
# ```manuscript
# let pages = map_concurrent(urls, 4, fn url: fetch(url))
# ```
export fn map_concurrent[T: Clonable, U: Clonable](
    items: List[T],
    limit: Int,
    work: fn(T) U
) List[U]!TaskError:
    if limit < 1:
        panic("map_concurrent: limit must be at least 1, found {limit}")

    let job = share(work)
    let pending = share(items.clone())
    let cursor = share(0)
    let done: Shared[Map[Int, U]] = share(Map[Int, U]())
    var group = TaskGroup[Unit]()

    for round in 0..limit.min(items.length()):
        let source = pending
        let next = cursor
        let out = done
        let run = job
        group.spawn(fn _channel: worker(source, next, out, run), none)

    try group.wait()

    var results: List[U] = []
    let finished = done.get()
    for index in 0..items.length():
        if let value = finished.get(index):
            results.append(value.clone())
    return ok(results)

fn worker[T: Clonable, U: Clonable](
    source: Shared[List[T]],
    next: Shared[Int],
    out: Shared[Map[Int, U]],
    work: Shared[fn(T) U]
) Unit:
    while true:
        var position = lock(next)
        let index = position.value
        if index >= source.get().length():
            return unit

        position.value = index + 1
        position.close().get(none)

        let value = work.get()(source.get()[index])
        var store = lock(out)
        store.value[index] = value

# What a `Cache` keeps for one key.
export opaque type CacheEntry[V]:
    # The stored value, returned to callers as a copy.
    value: V
    # When the value stops being served, or `none` for never.
    expires: Instant?
    # Internal state: the use counter that marks this entry's newest place in the recency order.
    stamp: Int

# A use of a key, as recorded in a cache's recency order.
export opaque type Use[K]:
    # The key that was used.
    key: K
    # The cache counter at that use.
    stamp: Int

# A bounded key-value cache that evicts the least recently used entry when full, and drops entries older than `ttl`.
# `get` returns a copy of the value, so cached values are never shared with callers.
#
# ```manuscript
# var cache = Cache[String, Int](capacity: 100, ttl: seconds(60))
# cache.set("a", 1)
# let hit = cache.get("a").get(0)
# ```
export type Cache[K: Hashable & Clonable, V: Clonable]:
    # Most entries held; at least 1.
    capacity: Int
    # How long an entry is served after it was set; `none` keeps it until evicted.
    ttl: Duration? = none
    # Internal state: the entries by key.
    entries: Map[K, CacheEntry[V]] = Map[K, CacheEntry[V]]()
    # Internal state: keys in order of use, oldest first; entries made stale by a later use are skipped.
    order: Deque[Use[K]] = Deque[Use[K]]()
    # Internal state: the counter behind `CacheEntry.stamp`.
    clock: Int = 0

impl Cache[K, V]:
    # The number of live entries, counting ones whose ttl passed but were not yet looked up.
    fn length() Int:
        return self.entries.length()

    # Notes `key` as the most recently used.
    var fn touch(key: K) Unit:
        self.clock += 1
        if var entry = self.entries[key]?:
            entry.stamp = self.clock
        self.order.push_back(Use(key: key.clone(), stamp: self.clock))
        if self.order.length() > self.capacity * 4 + 16:
            self.compact()

    # Drops order records that a later use made stale.
    var fn compact() Unit:
        var fresh = Deque[Use[K]]()
        while not self.order.is_empty():
            if let record = self.order.pop_front():
                if let entry = self.entries.get(record.key):
                    if entry.stamp == record.stamp:
                        fresh.push_back(record)
        self.order = fresh

    # Returns a copy of the value for `key` and marks it recently used; `none` when absent or older than the ttl.
    var fn get(key: K) V?:
        var live: V? = none
        var stale = false

        if let entry = self.entries.get(key):
            if let limit = entry.expires:
                stale = monotonic().compare(limit) >= 0
            if not stale:
                live = entry.value.clone()

        if stale:
            self.entries.remove(key)
            return none

        if live.is_some():
            self.touch(key)
        return live

    # Stores `value` under `key`, replacing any entry, and evicts the least recently used entry if the cache is over capacity.
    var fn set(key: K, value: V) Unit:
        if self.capacity < 1:
            panic("Cache: capacity must be at least 1, found {self.capacity}")

        var expires: Instant? = none
        if let life = self.ttl:
            expires = monotonic().shift(life)
        self.entries[key.clone()] = CacheEntry(value: value, expires: expires, stamp: 0)
        self.touch(key)
        while self.entries.length() > self.capacity:
            self.evict_oldest()

    # Removes the least recently used entry.
    var fn evict_oldest() Unit:
        while not self.order.is_empty():
            if let record = self.order.pop_front():
                if let entry = self.entries.get(record.key):
                    if entry.stamp == record.stamp:
                        self.entries.remove(record.key)
                        return unit

    # Removes `key`; nothing happens when it is absent.
    var fn remove(key: K) Unit:
        self.entries.remove(key)

    # Returns the value for `key`, computing and storing it with `create` when missing or expired.
    var fn get_or_set(key: K, create: fn() V) V:
        if let hit = self.get(key.clone()):
            return hit

        let made = create()
        self.set(key.clone(), made.clone())
        return made
