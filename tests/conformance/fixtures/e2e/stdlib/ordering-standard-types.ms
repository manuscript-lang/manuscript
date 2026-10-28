# conform: tags=stdlib-time,stdlib-math,testing
# conform: phase=test
from "@std/test.ms" import expect_equal
from "@std/time.ms" import seconds, parse_timestamp
from "@std/math.ms" import from_int
from "@std/decimal.ms" import Decimal

test "Duration orders with min, max and clamp":
    try expect_equal(seconds(3).min(seconds(5)), seconds(3))
    try expect_equal(seconds(3).max(seconds(5)), seconds(5))
    try expect_equal(seconds(9).clamp(seconds(1), seconds(5)), seconds(5))
    try expect_equal(seconds(-9).clamp(seconds(1), seconds(5)), seconds(1))
    try expect_equal(seconds(3).clamp(seconds(1), seconds(5)), seconds(3))

test "Timestamp orders with min, max and clamp":
    let early = parse_timestamp("2024-01-01T00:00:00Z").get()
    let late = parse_timestamp("2025-01-01T00:00:00Z").get()
    try expect_equal(early.min(late).to_string(), "2024-01-01T00:00:00Z")
    try expect_equal(early.max(late).to_string(), "2025-01-01T00:00:00Z")
    try expect_equal(early.clamp(late, late).to_string(), "2025-01-01T00:00:00Z")

test "Decimal orders with min, max and clamp":
    let a = (150).to_decimal()
    let b = (7).to_decimal()
    try expect_equal(a.min(b).to_fixed(0, none).get(), "7")
    try expect_equal(a.max(b).to_fixed(0, none).get(), "150")
    try expect_equal(a.clamp(b, b).to_fixed(0, none).get(), "7")

test "BigInt orders with min, max and clamp":
    try expect_equal(from_int(-4).min(from_int(2)).to_string_radix(10), "-4")
    try expect_equal(from_int(-4).max(from_int(2)).to_string_radix(10), "2")
    try expect_equal(
        from_int(40).clamp(from_int(1), from_int(5)).to_string_radix(10), "5"
    )
