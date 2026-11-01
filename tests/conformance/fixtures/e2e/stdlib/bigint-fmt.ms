# conform: tags=control-flow,formatter,interpolation,modules,optional,parser,stdlib-bigint,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/bigint.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import parse, from_int, BigInt, BigIntError from "@std/math/math.ms"

test "big integers exceed machine range without losing precision":
    let big = try parse("9223372036854775808", 10)
    try expect_false(not big.to_int().is_none())
    try expect_equal(big.subtract(from_int(1)).to_int(), 9223372036854775807)
    try expect_equal(from_int(7).multiply(from_int(6)).to_string_radix(10), "42")
    try expect_equal((try from_int(-7).divide(from_int(3))).to_int(), -2)
    try expect_equal((try from_int(-7).remainder(from_int(3))).to_int(), -1)
    try expect_equal(from_int(5).bit_xor(from_int(3)).to_int(), 6)

test "big integers validate digits budgets and zero divisors":
    let invalid: BigInt!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(from_int(1).divide(from_int(0)), invalid)

    let limited: BigInt!BigIntError = error(BigIntError.LimitExceeded)
    try expect_equal(parse("123", 10, 2), limited)

    let malformed: BigInt!BigIntError = error(BigIntError.InvalidData)
    try expect_equal(parse("1_0", 10), malformed)

test "big integer budgets exclude at most one leading sign before validation":
    let limited: BigInt!BigIntError = error(BigIntError.LimitExceeded)
    let malformed: BigInt!BigIntError = error(BigIntError.InvalidData)

    for text in ["+-1", "-+1", "++1", "--1"]:
        if parse(text, 10, 1) != limited: return fail(
            "second sign must count toward budget: {text}"
        )
        if parse(text, 10, 2) != malformed: return fail(
            "second sign must fail syntax validation: {text}"
        )

    for text in ["1", "+1", "-1"]:
        try expect_false(parse(text, 10, 1).is_error())
        try expect_equal(parse(text, 10, 0), limited)

test "big integers support sign pow shifts and conversion":
    let five = from_int(5)
    try expect_equal(five.negate().to_int(), -5)
    try expect_equal(five.negate().abs().to_int(), 5)
    try expect_equal(five.negate().sign(), -1)
    try expect_equal(from_int(0).sign(), 0)
    try expect_equal(five.bit_not().to_int(), -6)
    try expect_equal(
        (try from_int(2).pow(100)).to_string_radix(10),
        "1267650600228229401496703205376"
    )
    try expect_equal((try five.shift_left(3)).to_int(), 40)
    try expect_equal((try from_int(-5).shift_right(1)).to_int(), -3)
    try expect_equal(
        (try from_int(1).shift_left(70)).to_float(), 1180591620717411303424.0
    )

    let invalid: BigInt!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(five.pow(-1), invalid)
    try expect_equal(five.shift_left(-1), invalid)

    let limited: BigInt!BigIntError = error(BigIntError.LimitExceeded)
    try expect_equal(from_int(2).pow(100000000), limited)
    try expect_equal(five.shift_left(100000000), limited)
