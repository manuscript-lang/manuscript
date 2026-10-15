import {
    duration,
    clock,
    wall_clock,
    timestamp,
    parse_timestamp,
    TimeError
} from "@std/time.ms"
import panic from "@std/faults.ms"

test "duration arithmetic and conversion":
    let interval = duration(nanoseconds: 1500000000)
    if (
        interval.nanoseconds != 1500000000
        or interval.microseconds != 1500000
        or interval.milliseconds != 1500
    ):
        return panic("duration integer conversion")
    if (interval.seconds != 1.5 or 90.seconds.minutes != 1.5 or 90.minutes.hours != 1.5):
        return panic("duration fractional conversion")

    let negative = duration(-1500001)
    if negative.microseconds != -1500 or negative.milliseconds != -1:
        return panic("duration truncation")
    if (
        interval.add(1.seconds).subtract(500.milliseconds).multiply(3).divide(
            2
        ) != 3.seconds
    ):
        return panic("duration arithmetic")
    if duration(-7).divide(3) != duration(-2) or interval.negate().abs() != interval:
        return panic("duration sign and division")
    if (
        interval.compare(2.seconds) != -1
        or interval.compare(interval) != 0
        or interval.compare(1.seconds) != 1
    ):
        return panic("duration comparison")

    let captured_interval = interval
    let convert: fn() -> Float = fn() -> Float: captured_interval.seconds
    if convert() != 1.5:
        return panic("captured duration accessor")

test "monotonic instant methods":
    let start = clock().now()
    let later = start.shift(2.seconds)
    if (
        later.difference(start) != 2.seconds
        or start.difference(later) != duration((-2000000000))
    ):
        return panic("instant difference")
    if (
        start.compare(later) != -1
        or later.compare(start) != 1
        or start.compare(start) != 0
    ):
        return panic("instant comparison")
    if later.shift(duration(-2000000000)) != start:
        return panic("instant negative shift")

test "timestamp methods and expected range failures":
    let value = match timestamp(seconds: -1, nanoseconds: 500000000):
        ok(value): value
        error(_):
            return panic("timestamp construction failed")

    if (
        value.unix_seconds != -1
        or value.nanoseconds != 500000000
        or value.to_string() != "1969-12-31T23:59:59.5Z"
    ):
        return panic("timestamp components")

    let later = match value.shift(1500.milliseconds):
        ok(later): later
        error(_):
            return panic("timestamp shift failed")

    if (
        later.unix_seconds != 1
        or later.nanoseconds != 0
        or later.compare(value) != 1
        or value.compare(later) != -1
    ):
        return panic("timestamp shift and comparison")

    match later.difference(value):
        ok(delta):
            if delta != 1500.milliseconds:
                return panic("timestamp difference")

        error(_):
            return panic("timestamp difference failed")

    match parse_timestamp("2026-10-12T01:00:00+01:00"):
        ok(value):
            if value.to_string() != "2026-10-12T00:00:00Z" or value.compare(value) != 0:
                return panic("timestamp UTC normalization")

        error(_):
            return panic("timestamp parse failed")

    let maximum = match timestamp(seconds: 253402300799, nanoseconds: 999999999):
        ok(maximum): maximum
        error(_):
            return panic("maximum timestamp failed")

    match maximum.shift(duration(1)):
        error(cause):
            if cause != TimeError.OutOfRange:
                return panic("unexpected timestamp range error")

        _:
            return panic("timestamp shift must reject year 10000")

    let minimum = match timestamp(seconds: -62135596800, nanoseconds: 0):
        ok(minimum): minimum
        error(_):
            return panic("minimum timestamp failed")

    match maximum.difference(minimum):
        error(cause):
            if cause != TimeError.OutOfRange:
                return panic("unexpected timestamp difference error")

        _:
            return panic("timestamp difference must reject duration overflow")

    if maximum.compare(minimum) != 1:
        return panic("timestamp compare must work across full range")

    let now = wall_clock().now()

    match parse_timestamp(now.to_string()):
        ok(value):
            if value != now:
                return panic("wall clock roundtrip")

        error(_):
            return panic("wall clock formatting failed")
