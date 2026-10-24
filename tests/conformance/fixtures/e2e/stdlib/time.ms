# conform: tags=control-flow,interpolation,modules,stdlib-testing,stdlib-time,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/time.ms
from "@std/testing.ms" import expect_equal, expect_false, fail
from "@std/time.ms" import (
    timestamp, parse_timestamp, from_calendar, local_zone, Timestamp, TimeError, clock,
    wall_clock, sleep
)

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
        if parse_timestamp(text) != out_of_range: return fail(f"range {text}")

test "calendar fields follow the requested zone":
    let moment = try parse_timestamp("2024-03-10T12:30:15.250Z")
    let utc = try moment.calendar("UTC")
    try expect_equal(utc.year, 2024)
    try expect_equal(utc.month, 3)
    try expect_equal(utc.day, 10)
    try expect_equal(utc.weekday, 0)
    try expect_equal(utc.day_of_year, 70)
    try expect_equal(utc.nanosecond, 250000000)

    let ny = try moment.calendar("America/New_York")
    try expect_equal(ny.hour, 8)
    try expect_equal(ny.offset_seconds, -14400)

    let fixed = try moment.calendar("+05:30")
    try expect_equal(fixed.hour, 18)
    try expect_equal(fixed.minute, 0)

test "format renders tokens and from_calendar round trips":
    let moment = try parse_timestamp("2024-03-10T12:30:15.250Z")
    try expect_equal(
        (try moment.format("YYYY-MM-DD HH:mm:ss.SSS ZZ", "+05:30")),
        "2024-03-10 18:00:15.250 +05:30"
    )

    let back = try from_calendar(2024, 3, 10, 8, 30, 15, 250000000, "America/New_York")
    try expect_equal(back, moment)

test "calendar rejects unknown zones and impossible dates":
    let bad_zone: Result[Timestamp, TimeError] = error(TimeError.InvalidInput)
    try expect_equal(from_calendar(2024, 1, 1, 0, 0, 0, 0, "Nowhere/Land"), bad_zone)

    let bad_date: Result[Timestamp, TimeError] = error(TimeError.OutOfRange)
    try expect_equal(from_calendar(2023, 2, 29, 0, 0, 0, 0, "UTC"), bad_date)
    try expect_false(local_zone() == "")
