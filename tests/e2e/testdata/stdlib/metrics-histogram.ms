import (
    expect_equal, expect_true, expect_fault from "@std/test/test.ms",
    nan, infinity from "@std/math/math.ms",
    histogram from "@std/data/histogram.ms",
    milliseconds from "@std/time.ms",
)

test "histogram summarizes exact small values":
    var h = histogram()
    try expect_true(h.minimum().is_none())
    try expect_true(h.percentile(50.0).is_none())
    for value in 1..11: h.record(value)
    try expect_equal(h.count(), 10)
    try expect_equal(h.minimum().get(0), 1)
    try expect_equal(h.maximum().get(0), 10)
    try expect_equal(h.mean(), 5.5)
    try expect_equal(h.percentile(50.0).get(0), 5)
    try expect_equal(h.percentile(100.0).get(0), 10)
    try expect_equal(h.percentile(0.0).get(0), 1)

test "histogram buckets large values within three percent and caps at the maximum":
    var h = histogram()
    for value in 0..1000: h.record(1000000 + value * 1000)

    let p99 = h.percentile(99.0).get(0)
    try expect_true(p99 >= 1989000 and p99 <= 1999000 * 103 / 100)
    try expect_equal(h.percentile(100.0).get(0), 1999000)
    h.reset()
    try expect_equal(h.count(), 0)

test "histogram times a span and returns its result":
    var h = histogram()
    let answer = h.time(fn: 42)
    try expect_equal(answer, 42)
    try expect_equal(h.count(), 1)
    h.record_duration(milliseconds(2))
    try expect_equal(h.maximum().get(0) >= 2000000, true)

test "histogram answers for the highest valid Int bucket":
    var h = histogram()
    h.record(9223372036854775807)
    try expect_equal(h.percentile(100.0).get(0), 9223372036854775807)
    try expect_equal(h.percentile(50.0).get(0), 9223372036854775807)

    var low_edge = histogram()
    low_edge.record(9079256848778919936)
    try expect_equal(low_edge.percentile(100.0).get(0), 9079256848778919936)

fn discard_percentile(value: Int?) Unit:
    return unit

test "histogram rejects invalid percentiles whether empty or populated":
    var h = histogram()

    for populated in [false, true]:
        if populated: h.record(10)

        for p in [nan, -nan, infinity, -infinity, -0.1, 100.1]:
            let message = try expect_fault(fn: discard_percentile(h.percentile(p)))
            try expect_true(message.contains("must be within 0.0 and 100.0"))

        for p in [-0.0, 0.0, 0.1, 50.0, 99.9, 100.0]:
            if populated:
                try expect_equal(h.percentile(p), 10)
            else:
                try expect_true(h.percentile(p).is_none())

        try expect_equal(h.count(), if populated: 1 else: 0)

test "histogram percentile returns the observation at an exact rank":
    for count in [25, 50]:
        var h = histogram()
        for value in 1..(count + 1):
            h.record(value)
        for p in [14, 28, 56]:
            try expect_equal(h.percentile(p.to_float()), (p * count + 99) / 100)
