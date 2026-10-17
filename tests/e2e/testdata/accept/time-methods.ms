import {duration, clock, wall_clock, timestamp, parse_timestamp, TimeError} from "@std/time.ms"
import panic from "@std/faults.ms"

test "duration arithmetic and conversion":
    let interval = duration(nanoseconds: 1500000000)
    if (
        interval.to_nanoseconds() != 1500000000
        or interval.to_microseconds() != 1500000
        or interval.to_milliseconds() != 1500
    ):
        return panic("duration integer conversion")
    if (
        interval.to_seconds() != 1.5
        or 90.seconds.to_minutes() != 1.5
        or 90.minutes.to_hours() != 1.5
    ):
        return panic("duration fractional conversion")

    let negative = duration(-1500001)
    if negative.to_microseconds() != -1500 or negative.to_milliseconds() != -1:
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

    let convert = interval.to_seconds
    if convert() != 1.5:
        return panic("bound duration method")

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
    let value = timestamp(seconds: -1, nanoseconds: 500000000).unwrap()
    if (
        value.unix_seconds() != -1
        or value.nanoseconds() != 500000000
        or value.to_string() != "1969-12-31T23:59:59.5Z"
    ):
        return panic("timestamp components")

    let later = value.shift(1500.milliseconds).unwrap()
    if (
        later.unix_seconds() != 1
        or later.nanoseconds() != 0
        or later.compare(value) != 1
        or value.compare(later) != -1
    ):
        return panic("timestamp shift and comparison")
    if later.difference(value).unwrap() != 1500.milliseconds:
        return panic("timestamp difference")

    let parsed = parse_timestamp("2026-10-12T01:00:00+01:00").unwrap()
    if parsed.to_string() != "2026-10-12T00:00:00Z" or parsed.compare(parsed) != 0:
        return panic("timestamp UTC normalization")

    let maximum = timestamp(seconds: 253402300799, nanoseconds: 999999999).unwrap()
    let shifted = maximum.shift(duration(1))
    if shifted.is_ok():
        return panic("timestamp shift must reject year 10000")
    if shifted.unwrap_error() != TimeError.OutOfRange:
        return panic("unexpected timestamp range error")

    let minimum = timestamp(seconds: -62135596800, nanoseconds: 0).unwrap()
    let difference = maximum.difference(minimum)
    if difference.is_ok():
        return panic("timestamp difference must reject duration overflow")
    if difference.unwrap_error() != TimeError.OutOfRange:
        return panic("unexpected timestamp difference error")
    if maximum.compare(minimum) != 1:
        return panic("timestamp compare must work across full range")

    let now = wall_clock().now()
    if (now.to_string() | parse_timestamp | .unwrap()) != now:
        return panic("wall clock roundtrip")
