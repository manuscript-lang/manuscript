import {timestamp, parse_timestamp, Timestamp, TimeError, clock, wall_clock, sleep} from "@std/time.ms"
import panic from "@std/faults.ms"

test "timestamps preserve nanoseconds and shift across epoch":
    let epoch = try timestamp(0, 123)
    if epoch.unix_seconds() != 0 or epoch.nanoseconds() != 123: return panic(
        "timestamp units"
    )
    if (try parse_timestamp(epoch.to_string())) != epoch: return panic(
        "timestamp roundtrip"
    )

    let later = try epoch.shift(2.seconds)
    if (try later.difference(epoch)) != 2.seconds: return panic("time difference")
    if (try later.shift((-2).seconds)) != epoch: return panic("negative shift")

test "time rejects invalid timestamps and out of range nanoseconds":
    let invalid: Result[Timestamp, TimeError] = error(TimeError.InvalidData)
    if parse_timestamp("2024-02-30T00:00:00Z") != invalid: return panic(
        "invalid calendar date"
    )

    let out_of_range: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    if timestamp(0, 1000000000) != out_of_range: return panic("nanosecond range")

test "host clocks are usable and zero sleep completes":
    let monotonic = clock()
    let before = monotonic.now()
    sleep(0.milliseconds)
    if monotonic.now() < before: return panic("clock went backwards")

    let now = wall_clock().now()
    if (try parse_timestamp(now.to_string())) != now: return panic(
        "wall clock roundtrip"
    )

test "parse_timestamp reports offsets that leave years 1 through 9999 as out of range":
    let out_of_range: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    for text in ["0001-01-01T00:00:00+00:01", "9999-12-31T23:59:59-00:01"]:
        if parse_timestamp(text) != out_of_range: return panic("range {text}")
