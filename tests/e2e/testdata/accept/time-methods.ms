import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {duration, clock, wall_clock, timestamp, parse_timestamp, TimeError} from "@std/time.ms"

test "duration arithmetic and conversion":
    let interval = duration(nanoseconds: 1500000000)
    (
        (
            interval.to_nanoseconds() != 1500000000
            or interval.to_microseconds() != 1500000
            or interval.to_milliseconds() != 1500
        )
    ) | try expect_false
    (
        (
            interval.to_seconds() != 1.5
            or 90.seconds.to_minutes() != 1.5
            or 90.minutes.to_hours() != 1.5
        )
    ) | try expect_false
    let negative = duration(-1500001)
    (negative.to_microseconds() != -1500 or negative.to_milliseconds() != -1) | try expect_false
    (
        (
            interval.add(1.seconds).subtract(500.milliseconds).multiply(
                3
            ).divide(2) != 3.seconds
        )
    ) | try expect_false
    (duration(-7).divide(3) != duration(-2) or interval.negate().abs() != interval) | try expect_false
    (
        (
            interval.compare(2.seconds) != -1
            or interval.compare(interval) != 0
            or interval.compare(1.seconds) != 1
        )
    ) | try expect_false
    let convert = interval.to_seconds
    convert() | try expect_equal(expected: 1.5)

test "monotonic instant methods":
    let start = clock().now()
    let later = start.shift(2.seconds)
    (
        (
            later.difference(start) != 2.seconds
            or start.difference(later) != duration((-2000000000))
        )
    ) | try expect_false
    (
        (
            start.compare(later) != -1
            or later.compare(start) != 1
            or start.compare(start) != 0
        )
    ) | try expect_false
    later.shift(duration(-2000000000)) | try expect_equal(expected: start)

test "timestamp methods and expected range failures":
    let value = match timestamp(seconds: -1, nanoseconds: 500000000):
        ok(value): value
        error(_):
            return fail("timestamp construction failed")

    (
        (
            value.unix_seconds() != -1
            or value.nanoseconds() != 500000000
            or value.to_string() != "1969-12-31T23:59:59.5Z"
        )
    ) | try expect_false

    let later = match value.shift(1500.milliseconds):
        ok(later): later
        error(_):
            return fail("timestamp shift failed")

    (
        (
            later.unix_seconds() != 1
            or later.nanoseconds() != 0
            or later.compare(value) != 1
            or value.compare(later) != -1
        )
    ) | try expect_false

    match later.difference(value):
        ok(delta):
            try expect_equal(delta, 1500.milliseconds)
        error(_):
            return fail("timestamp difference failed")

    match parse_timestamp("2026-10-12T01:00:00+01:00"):
        ok(value):
            (
                (
                    (
                        value.to_string() != "2026-10-12T00:00:00Z"
                        or value.compare(value) != 0
                    )
                ) | try expect_false
            )
        error(_):
            return fail("timestamp parse failed")

    let maximum = match timestamp(seconds: 253402300799, nanoseconds: 999999999):
        ok(maximum): maximum
        error(_):
            return fail("maximum timestamp failed")

    match maximum.shift(duration(1)):
        error(cause):
            try expect_equal(cause, TimeError.OutOfRange)
        _:
            return fail("timestamp shift must reject year 10000")

    let minimum = match timestamp(seconds: -62135596800, nanoseconds: 0):
        ok(minimum): minimum
        error(_):
            return fail("minimum timestamp failed")

    match maximum.difference(minimum):
        error(cause):
            try expect_equal(cause, TimeError.OutOfRange)
        _:
            return fail("timestamp difference must reject duration overflow")

    maximum.compare(minimum) | try expect_equal(expected: 1)
    let now = wall_clock().now()

    match parse_timestamp(now.to_string()):
        ok(value):
            try expect_equal(value, now)
        error(_):
            return fail("wall clock formatting failed")
