import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {timestamp, parse_timestamp, Timestamp, TimeError, clock, wall_clock, sleep} from "@std/time.ms"

test "timestamps preserve nanoseconds and shift across epoch":
    let epoch = try timestamp(0, 123)
    try expect_false(epoch.unix_seconds() != 0 or epoch.nanoseconds() != 123)
    try expect_equal((try parse_timestamp(epoch.to_string())), epoch)
    let later = try epoch.shift(2.seconds)
    try expect_equal((try later.difference(epoch)), 2.seconds)
    try expect_equal((try later.shift((-2).seconds)), epoch)

test "time rejects invalid timestamps and out of range nanoseconds":
    let invalid: Result[Timestamp, TimeError] = error(TimeError.InvalidData)
    try expect_equal(parse_timestamp("2024-02-30T00:00:00Z"), invalid)
    let out_of_range: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    try expect_equal(timestamp(0, 1000000000), out_of_range)

test "host clocks are usable and zero sleep completes":
    let monotonic = clock()
    let before = monotonic.now()
    sleep(0.milliseconds)
    try expect_false(monotonic.now() < before)
    let now = wall_clock().now()
    try expect_equal((try parse_timestamp(now.to_string())), now)

test "parse_timestamp reports offsets that leave years 1 through 9999 as out of range":
    let out_of_range: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    for text in ["0001-01-01T00:00:00+00:01", "9999-12-31T23:59:59-00:01"]:
        if parse_timestamp(text) != out_of_range: return fail("range {text}")
