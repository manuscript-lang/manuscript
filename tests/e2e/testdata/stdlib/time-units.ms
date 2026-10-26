from "@std/testing.ms" import expect_equal
from "@std/time.ms" import (
    duration,
    nanoseconds,
    microseconds,
    milliseconds,
    seconds,
    minutes,
    hours
)

test "unit constructors build exact nanosecond counts":
    try expect_equal(nanoseconds(7).to_nanoseconds(), 7)
    try expect_equal(microseconds(3).to_nanoseconds(), 3000)
    try expect_equal(milliseconds(250).to_nanoseconds(), 250000000)
    try expect_equal(seconds(2).to_nanoseconds(), 2000000000)
    try expect_equal(minutes(2).to_nanoseconds(), 120000000000)
    try expect_equal(hours(1).to_nanoseconds(), 3600000000000)
    try expect_equal(seconds(2), duration(nanoseconds: 2000000000))

test "unit constructors accept negative values":
    try expect_equal(seconds(-1).to_nanoseconds(), -1000000000)
    try expect_equal(milliseconds(-5).to_nanoseconds(), -5000000)
    try expect_equal(hours(-2), hours(2).negate())

test "unit constructors round trip through to_ readers":
    try expect_equal(microseconds(1500).to_microseconds(), 1500)
    try expect_equal(milliseconds(1500).to_milliseconds(), 1500)
    try expect_equal(milliseconds(1500).to_seconds(), 1.5)
    try expect_equal(seconds(90).to_minutes(), 1.5)
    try expect_equal(minutes(90).to_hours(), 1.5)
    try expect_equal(seconds(90).add(milliseconds(500)).to_milliseconds(), 90500)

test "durations read as human spans in interpolation and to_string":
    try expect_equal(f"{seconds(90).add(milliseconds(500))}", "1m30.5s")
    try expect_equal(f"{milliseconds(250)}", "250ms")
    try expect_equal(f"{microseconds(1500)}", "1.5ms")
    try expect_equal(f"{nanoseconds(7)}", "7ns")
    try expect_equal(f"{hours(2)}", "2h0m0s")
    try expect_equal(f"{seconds(-2)}", "-2s")
    try expect_equal(duration(nanoseconds: 0).to_string(), "0s")
    try expect_equal(f"{hours(1).add(seconds(5))}", "1h0m5s")

test "extreme durations format, including the minimum":
    try expect_equal(
        duration(nanoseconds: 9223372036854775807).to_string(),
        "2562047h47m16.854775807s"
    )
    try expect_equal(
        duration(nanoseconds: -9223372036854775807 - 1).to_string(),
        "-2562047h47m16.854775808s"
    )
    try expect_equal(f"{nanoseconds(-1500)}", "-1.5µs")
    try expect_equal(f"{nanoseconds(-999999999)}", "-999.999999ms")
