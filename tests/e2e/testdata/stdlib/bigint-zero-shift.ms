import expect_equal from "@std/test/test.ms"
import from_int, BigInt, BigIntError from "@std/math/math.ms"

test "zero shifts have zero result bits at every nonnegative count":
    for count in [0, 16777216, 16777217, 9223372036854775807]:
        try expect_equal((try from_int(0).shift_left(count)).to_int(), 0)

    let invalid: BigInt!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(from_int(0).shift_left(-1), invalid)

test "nonzero shifts still enforce the result bit budget":
    let limit = 16777216
    let limited: BigInt!BigIntError = error(BigIntError.LimitExceeded)
    try expect_equal(from_int(1).shift_left(limit), limited)
    try expect_equal(from_int(-1).shift_left(limit), limited)

    let largest_power = try from_int(1).shift_left(limit - 1)
    try expect_equal((try largest_power.shift_right(limit - 1)).to_int(), 1)
