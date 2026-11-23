// ms: allow_effect std.clock.read

import (
	ceil, leading_zeros, shift_left, shift_right from "@std/math/math.ms",
	Duration, monotonic from "@std/time.ms",
)

// Buckets below this value are exact; above it each power of two is split into 32 steps
// (about 3% error).
EXACT := 64
// Bucket count: 64 exact values plus 32 steps for each of the 57 higher powers of two.
BUCKETS := 1888

/*
A latency histogram. It records non-negative `Int` values, usually nanoseconds, in fixed
memory and answers count, extremes, mean and percentiles.

Values below 64 are exact. Larger values fall in buckets about 3% wide, so a percentile
is an upper bound within that error. A histogram has one owner; other promises send
their observations to that owner over a `pipe`.

Example: `latency.time(fn: handle(request))` records one span, and
`latency.percentile(99.0)` returns the value that 99% of observations do not exceed.
*/
export opaque type Histogram:
	// Observation count per bucket.
	counts: List[Int]
	// Observations recorded since creation or the last reset.
	total: Int
	// Exact sum of every observation, as `sum_wraps` times 2^63 plus `sum`.
	sum: Int
	sum_wraps: Int
	// Smallest observation; meaningful only when `total` is above zero.
	low: Int
	// Largest observation; meaningful only when `total` is above zero.
	high: Int

// Adds one observation. A negative value is recorded as 0, so a clock that steps back
// counts as an instant measurement.
fn var Histogram.record(value: Int) Void:
	observed := value.max(0)
	index := bucket_of(observed)
	self.counts[index] += 1
	if self.total == 0 or observed < self.low: self.low = observed
	if observed > self.high: self.high = observed
	self.total += 1

	room := 9223372036854775807 - observed

	if self.sum <= room:
		self.sum += observed
	else:
		self.sum -= room + 1
		self.sum_wraps += 1

// Adds one duration as nanoseconds. A negative duration is recorded as 0, like
// `record`.
fn var Histogram.record_duration(elapsed: Duration) Void:
	self.record(elapsed.to_nanoseconds())

// Runs `work`, records how long it took in nanoseconds on the monotonic clock, and
// returns its result. A normal return, including an error Result, is recorded; a
// fault or cancellation that prevents returning is not.
fn var Histogram.time[T](work: fn() T) T:
	started := monotonic()
	result := work()
	self.record_duration(monotonic().difference(started))
	return result

// Observations recorded so far.
fn Histogram.count() Int:
	return self.total

// Smallest observation, or null when empty.
fn Histogram.min() Int?:
	if self.total == 0: return null
	return self.low

// Largest observation, or null when empty.
fn Histogram.max() Int?:
	if self.total == 0: return null
	return self.high

// Mean of the observations, or 0.0 when empty. It is exact, not bucketed.
fn Histogram.mean() Float:
	if self.total == 0: return 0.0

	sum := self.sum_wraps.to_float() * 9223372036854775808.0 + self.sum.to_float()
	return sum / self.total.to_float()

// Value at or below which `p` percent of observations fall, for `p` in 0.0 through
// 100.0; null when empty. The answer is the top of the matching bucket, never above
// the largest observation. A `p` outside the range gives null.
fn Histogram.percentile(p: Float) Int?:
	if not (p >= 0.0 and p <= 100.0) or self.total == 0: return null

	var rank = ceil(p * self.total.to_float() / 100.0).truncate_to_int().get_or(1)
	if rank < 1: rank = 1

	var seen = 0

	for index in 0..BUCKETS:
		seen += self.counts[index]
		if seen >= rank: return bucket_top(index).min(self.high)

	return self.high

// Discards every observation and returns the histogram to its empty state.
fn var Histogram.reset() Void:
	self.counts = zeros()
	self.total = 0
	self.sum = 0
	self.sum_wraps = 0
	self.low = 0
	self.high = 0

// Creates an empty histogram.
export fn histogram() Histogram:
	return Histogram(zeros(), 0, 0, 0, 0, 0)

fn zeros() List[Int]:
	var counts = List[Int](reserve: BUCKETS)
	for _index in 0..BUCKETS: counts.append(0)
	return counts

fn bucket_of(value: Int) Int:
	if value < EXACT: return value

	shift := 64 - leading_zeros(value) - 6
	return EXACT + (shift - 1) * 32 + (shift_right(value, shift) - 32)

// The largest value that falls in bucket `index`.
fn bucket_top(index: Int) Int:
	if index < EXACT: return index

	offset := index - EXACT
	shift := offset / 32 + 1
	low := shift_left(offset % 32 + 32, shift)
	return low + (shift_left(1, shift) - 1)
