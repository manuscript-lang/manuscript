import expect_equal from "@std/test.ms"
import from_int, BigInt, BigIntError from "@std/math.ms"

test "big integer powers enforce the exact result bit limit":
    let limit = 16777216
    let limited: BigInt!BigIntError = error(BigIntError.LimitExceeded)
    let largest_power = try from_int(2).pow(limit - 1)
    try expect_equal((try largest_power.shift_right(limit - 1)).to_int(), 1)
    try expect_equal(from_int(2).pow(limit), limited)
    try expect_equal(from_int(-2).pow(limit), limited)

    let power = try from_int(1).shift_left(limit / 3 + 1)
    let dense = power.subtract(from_int(1))
    try expect_equal(dense.pow(3), limited)
    try expect_equal(dense.negate().pow(3), limited)

test "constant big integer powers remain valid at huge exponents":
    let maximum = 9223372036854775807
    try expect_equal((try from_int(0).pow(maximum)).to_int(), 0)
    try expect_equal((try from_int(1).pow(maximum)).to_int(), 1)
    try expect_equal((try from_int(-1).pow(maximum)).to_int(), -1)
    try expect_equal((try from_int(-1).pow(maximum - 1)).to_int(), 1)
    try expect_equal((try from_int(0).pow(0)).to_int(), 1)
