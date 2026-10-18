import {expect_equal, expect_false, expect_ok} from "@std/testing.ms"
import {timestamp, parse_timestamp, Timestamp, TimeError, clock, wall_clock, sleep} from "@std/time.ms"

test "timestamps preserve nanoseconds and shift across epoch":
    let epoch = (timestamp(seconds: 0, nanoseconds: 123) | try expect_ok)
    (epoch.unix_seconds() != 0 or epoch.nanoseconds() != 123) | try expect_false
    parse_timestamp(epoch.to_string()) | try expect_ok | try expect_equal(
        expected: epoch
    )
    let later = (epoch.shift(2.seconds) | try expect_ok)
    later.difference(epoch) | try expect_ok | try expect_equal(expected: 2.seconds)
    later.shift((-2).seconds) | try expect_ok | try expect_equal(expected: epoch)

test "time rejects invalid timestamps and out of range nanoseconds":
    let invalid: Result[Timestamp, TimeError] = error(TimeError.InvalidData)
    parse_timestamp("2024-02-30T00:00:00Z") | try expect_equal(expected: invalid)
    let out_of_range: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    timestamp(seconds: 0, nanoseconds: 1000000000) | try expect_equal(
        expected: out_of_range
    )

test "host clocks are usable and zero sleep completes":
    let monotonic = clock()
    let before = monotonic.now()
    sleep(0.milliseconds)
    (monotonic.now() < before) | try expect_false
    let now = wall_clock().now()
    parse_timestamp(now.to_string()) | try expect_ok | try expect_equal(expected: now)
