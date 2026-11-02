import expect_equal, expect_true from "@std/test/test.ms"
import histogram from "@std/os/metrics.ms"
import milliseconds from "@std/os/time.ms"

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
