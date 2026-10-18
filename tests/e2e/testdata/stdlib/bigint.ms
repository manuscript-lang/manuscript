import {expect_equal, expect_ok, expect_true} from "@std/testing.ms"
import {parse, from_int, BigInt, BigIntError} from "@std/bigint.ms"

test "big integers exceed machine range without losing precision":
    let big = (parse(text: "9223372036854775808", radix: 10) | try expect_ok)
    (big.to_int().is_none()) | try expect_true
    (
        big.subtract(from_int(1)).to_int() | try expect_equal(
            expected: some(9223372036854775807)
        )
    )
    (
        from_int(7).multiply(from_int(6)).to_string(
            radix: 10
        ) | try expect_equal(expected: "42")
    )
    (from_int(-7).divide(from_int(3)) | try expect_ok).to_int() | try expect_equal(
        expected: some((-2))
    )
    (from_int(-7).remainder(from_int(3)) | try expect_ok).to_int() | try expect_equal(
        expected: some((-1))
    )
    from_int(5).bit_xor(from_int(3)).to_int() | try expect_equal(expected: some(6))

test "big integers validate digits budgets and zero divisors":
    let invalid: Result[BigInt, BigIntError] = error(BigIntError.InvalidInput)
    from_int(1).divide(from_int(0)) | try expect_equal(expected: invalid)
    let limited: Result[BigInt, BigIntError] = error(BigIntError.LimitExceeded)
    parse(text: "123", radix: 10, max_digits: 2) | try expect_equal(expected: limited)
    let malformed: Result[BigInt, BigIntError] = error(BigIntError.InvalidData)
    parse(text: "1_0", radix: 10) | try expect_equal(expected: malformed)
