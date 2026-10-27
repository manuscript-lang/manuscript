# conform: tags=formatter,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:237
from "@std/test.ms" import expect_equal

type Reading:
    celsius: Int

def parse_reading(text: String) -> Result[Reading, Error]:
    let celsius = try text.trim().parse_int().ok_or()
    return ok(Reading(celsius))

def to_fahrenheit(reading: Reading) -> Int:
    return reading.celsius * 9 / 5 + 32

def fahrenheit(text: String) -> Result[Int, Error]:
    let value = try parse_reading(text) | to_fahrenheit
    return ok(value)

test "pipe flow":
    try expect_equal(try fahrenheit(" 100 "), 212)
