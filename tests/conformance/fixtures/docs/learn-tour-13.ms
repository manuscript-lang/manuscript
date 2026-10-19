# conform: tags=modules,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=documentation/learn/tour.md:237
import expect_equal from "@std/testing.ms"

type Reading:
    celsius: Int

fn parse_reading(text: String) Result[Reading, Error]:
    let celsius = try text.trim().parse_int().ok_or()
    return ok(Reading(celsius))

fn to_fahrenheit(reading: Reading) Int:
    return reading.celsius * 9 / 5 + 32

fn fahrenheit(text: String) Result[Int, Error]:
    let value = try parse_reading(text) | to_fahrenheit
    return ok(value)

test "pipe flow":
    try expect_equal(try fahrenheit(" 100 "), 212)
