import panic from "@std/core.ms"
import ceil, leading_zeros, shift_left, shift_right from "@std/math/math.ms"
import Duration, monotonic from "@std/os/time.ms"

# Buckets below this value are exact; above it each power of two is split into 32 steps (about 3% error).
let EXACT = 64
# Bucket count: 64 exact values plus 32 steps for each of the 57 higher powers of two.
let BUCKETS = 1888

fn zeros() List[Int]:
    var counts = List[Int](reserve: BUCKETS)
    for _index in 0..BUCKETS: counts.append(0)
    return counts

fn bucket_of(value: Int) Int:
    if value < EXACT: return value

    let shift = 64 - leading_zeros(value) - 6
    return EXACT + (shift - 1) * 32 + (shift_right(value, shift) - 32)

# The largest value that falls in bucket `index`.
fn bucket_top(index: Int) Int:
    if index < EXACT: return index

    let offset = index - EXACT
    let shift = offset / 32 + 1
    let low = shift_left(offset % 32 + 32, shift)
    return low + shift_left(1, shift) - 1

# A latency histogram: records non-negative `Int` values, usually nanoseconds, in fixed memory and
# answers count, extremes, mean and percentiles. Values below 64 are exact and larger ones fall in
# buckets about 3% wide, so a percentile is an upper bound within that error. One histogram belongs to
# one task; share it between tasks behind a `Shared`.
#
#     var latency = histogram()
#     let answer = latency.time(fn: handle(request))
#     let slowest = latency.percentile(99.0)
export opaque type Histogram:
    # Observation count per bucket.
    counts: List[Int]
    # Observations recorded since creation or the last reset.
    total: Int
    # Exact sum of every observation.
    sum: Int
    # Smallest observation; meaningful only when `total` is above zero.
    low: Int
    # Largest observation; meaningful only when `total` is above zero.
    high: Int

impl Histogram:
    # Adds one observation. A negative value faults: it is a caller error, not data to clamp.
    var fn record(value: Int) Unit:
        if value < 0: panic("Histogram.record: value {value} must be at least 0")

        let index = bucket_of(value)
        self.counts[index] = self.counts[index] + 1
        if self.total == 0 or value < self.low: self.low = value
        if value > self.high: self.high = value
        self.total += 1
        self.sum += value

    # Adds one duration as nanoseconds. A negative duration faults like `record`.
    var fn record_duration(elapsed: Duration) Unit:
        self.record(elapsed.to_nanoseconds())

    # Runs `work`, records how long it took in nanoseconds on the monotonic clock, and returns its result.
    # A span that returns early or faults is not recorded.
    var fn time[T](work: fn() T) T:
        let started = monotonic()
        let result = work()
        self.record_duration(monotonic().difference(started))
        return result

    # Observations recorded so far.
    fn count() Int:
        return self.total

    # Smallest observation, or none when empty.
    fn minimum() Int?:
        if self.total == 0: return none

        return self.low

    # Largest observation, or none when empty.
    fn maximum() Int?:
        if self.total == 0: return none

        return self.high

    # Mean of the observations, or 0.0 when empty. It is exact, not bucketed.
    fn mean() Float:
        if self.total == 0: return 0.0

        return self.sum.to_float() / self.total.to_float()

    # Value at or below which `p` percent of observations fall, for `p` in 0.0 through 100.0; none when empty.
    # The answer is the top of the matching bucket, never above `maximum`. A `p` outside the range faults.
    fn percentile(p: Float) Int?:
        if p < 0.0 or p > 100.0: panic(
            "Histogram.percentile: p {p} must be within 0.0 and 100.0"
        )
        if self.total == 0: return none

        var rank = ceil(p / 100.0 * self.total.to_float()).truncate_to_int().get(1)
        if rank < 1: rank = 1

        var seen = 0

        for index in 0..BUCKETS:
            seen += self.counts[index]
            if seen >= rank: return bucket_top(index).min(self.high)

        return self.high

    # Discards every observation and returns the histogram to its empty state, keeping its memory.
    var fn reset() Unit:
        self.counts = zeros()
        self.total = 0
        self.sum = 0
        self.low = 0
        self.high = 0

# Creates an empty histogram.
export fn histogram() Histogram:
    return Histogram(zeros(), 0, 0, 0, 0)
