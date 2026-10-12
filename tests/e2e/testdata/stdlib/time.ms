import {timestamp, parse_timestamp, format_timestamp, unix_seconds, nanoseconds, shift, difference, Timestamp, TimeError, clock, wall_clock, sleep} from "@std/time.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "timestamps preserve nanoseconds and shift across epoch":
    let epoch = value(timestamp(seconds: 0, nanoseconds: 123))
    if unix_seconds(epoch) != 0 or nanoseconds(epoch) != 123: return panic("timestamp units")
    if value(parse_timestamp(format_timestamp(epoch))) != epoch: return panic("timestamp roundtrip")
    let later = value(shift(value: epoch, duration: 2.seconds))
    if value(difference(left: later, right: epoch)) != 2.seconds: return panic("time difference")
    if value(shift(value: later, duration: (-2).seconds)) != epoch: return panic("negative shift")

test "time rejects invalid timestamps and out of range nanoseconds":
    let invalid: Result[Timestamp, TimeError] = error(cause: TimeError.InvalidData)
    if parse_timestamp("2024-02-30T00:00:00Z") != invalid: return panic("invalid calendar date")
    let out_of_range: Result[Timestamp, TimeError] = error(cause: TimeError.OutOfRange)
    if timestamp(seconds: 0, nanoseconds: 1000000000) != out_of_range: return panic("nanosecond range")

test "host clocks are usable and zero sleep completes":
    let monotonic = clock()
    let before = monotonic.now()
    sleep(0.milliseconds)
    if monotonic.now() < before: return panic("clock went backwards")
    let now = wall_clock().now()
    if value(parse_timestamp(format_timestamp(now))) != now: return panic("wall clock roundtrip")
