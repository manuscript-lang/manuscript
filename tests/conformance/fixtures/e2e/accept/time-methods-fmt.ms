# conform: tags=formatter,modules,parser,stdlib-testing,stdlib-time,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/time-methods.ms
import expect_equal, expect_false from "@std/test.ms"
import nanoseconds, clock, wall_clock, timestamp, parse_timestamp, TimeError from "@std/time.ms"

test "duration arithmetic and conversion":
    let interval = nanoseconds(1500000000)
    try expect_false(
        (
            interval.to_nanoseconds() != 1500000000
            or interval.to_microseconds() != 1500000
            or interval.to_milliseconds() != 1500
        )
    )
    try expect_false(
        (
            interval.to_seconds() != 1.5
            or 90.seconds.to_minutes() != 1.5
            or 90.minutes.to_hours() != 1.5
        )
    )

    let negative = nanoseconds(-1500001)
    try expect_false(
        (
            negative.to_microseconds() != -1500
            or negative.to_milliseconds() != -1
        )
    )
    try expect_false(
        (
            interval.add(1.seconds).subtract(500.milliseconds).multiply(
                3
            ).divide(2) != 3.seconds
        )
    )
    try expect_false(
        (
            nanoseconds(-7).divide(3) != nanoseconds(-2)
            or interval.negate().abs() != interval
        )
    )
    try expect_false(
        (
            interval.compare(2.seconds) != -1
            or interval.compare(interval) != 0
            or interval.compare(1.seconds) != 1
        )
    )

    let convert = interval.to_seconds
    try expect_equal(convert(), 1.5)

test "monotonic instant methods":
    let start = clock().now()
    let later = start.shift(2.seconds)
    try expect_false(
        (
            later.difference(start) != 2.seconds
            or start.difference(later) != nanoseconds((-2000000000))
        )
    )
    try expect_false(
        (
            start.compare(later) != -1
            or later.compare(start) != 1
            or start.compare(start) != 0
        )
    )
    try expect_equal(later.shift(nanoseconds(-2000000000)), start)

test "timestamp methods and expected range failures":
    let value = try timestamp(-1, 500000000)
    try expect_false(
        (
            value.unix_seconds() != -1
            or value.nanoseconds() != 500000000
            or value.to_string() != "1969-12-31T23:59:59.5Z"
        )
    )

    let later = try value.shift(1500.milliseconds)
    try expect_false(
        (
            later.unix_seconds() != 1
            or later.nanoseconds() != 0
            or later.compare(value) != 1
            or value.compare(later) != -1
        )
    )

    let delta = try later.difference(value)
    try expect_equal(delta, 1500.milliseconds)

    let parsed = try parse_timestamp("2026-10-12T01:00:00+01:00")
    try expect_false(
        (
            parsed.to_string() != "2026-10-12T00:00:00Z"
            or parsed.compare(parsed) != 0
        )
    )

    let maximum = try timestamp(253402300799, 999999999)
    let shifted = maximum.shift(nanoseconds(1))
    try expect_false(shifted.is_ok())
    try expect_equal(shifted.err(), TimeError.OutOfRange)

    let minimum = try timestamp(-62135596800, 0)
    let difference = maximum.difference(minimum)
    try expect_false(difference.is_ok())
    try expect_equal(difference.err(), TimeError.OutOfRange)
    try expect_equal(maximum.compare(minimum), 1)

    let now = wall_clock().now()
    let roundtrip = try parse_timestamp(now.to_string())
    try expect_equal(roundtrip, now)
