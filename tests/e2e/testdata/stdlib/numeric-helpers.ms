import expect_equal, expect_true, expect_false from "@std/test/test.ms"
import (
    reverse_bits,
    reverse_bytes,
    shift_left,
    bit_xor,
    wrapping_multiply,
    exp2,
    round_to_even,
    copy_sign,
    sign_bit,
    next_after,
    fma,
    infinity,
    nan,
    min_float,
    max_float,
    BigInt,
    BigIntError,
    from_int,
    parse
) from "@std/math/math.ms"

test "bit and byte reversal map every position in a 64-bit pattern":
    try expect_equal(reverse_bits(0), 0)
    try expect_equal(reverse_bytes(-1), -1)

    for position in 0..64:
        let value = shift_left(1, position)
        try expect_equal(reverse_bits(value), shift_left(1, 63 - position))
        try expect_equal(
            reverse_bytes(value), shift_left(1, (7 - position / 8) * 8 + position % 8)
        )

    var value = 81985529216486895

    for unused in 0..256:
        try expect_equal(reverse_bits(reverse_bits(value)), value)
        try expect_equal(reverse_bytes(reverse_bytes(value)), value)
        value = bit_xor(
            wrapping_multiply(value, 6364136223846793005), -7046029254386353131
        )

test "base-two exponentiation includes underflow overflow and special values":
    try expect_equal(exp2(0.0), 1.0)
    try expect_equal(exp2(10.0), 1024.0)
    try expect_equal(exp2(-10.0), 0.0009765625)
    try expect_equal(exp2(-1074.0), min_float)
    try expect_equal(exp2(-1075.0), 0.0)
    try expect_equal(exp2(1024.0), infinity)
    try expect_equal(exp2(-infinity), 0.0)
    try expect_true(exp2(nan).is_nan())

test "ties-even rounding and sign helpers preserve IEEE sign distinctions":
    let values = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5]
    let expected = [0.0, 2.0, 2.0, 0.0, -2.0, -2.0]
    for i in 0..values.length():
        try expect_equal(round_to_even(values.get(i)), expected.get(i))
    try expect_true(sign_bit(round_to_even(-0.5)))
    try expect_true(sign_bit(round_to_even(-0.0)))
    try expect_false(sign_bit(round_to_even(0.5)))
    try expect_equal(round_to_even(infinity), infinity)
    try expect_equal(round_to_even(-infinity), -infinity)
    try expect_true(round_to_even(nan).is_nan())
    try expect_equal(copy_sign(-3.0, 1.0), 3.0)
    try expect_equal(copy_sign(3.0, -1.0), -3.0)
    try expect_true(sign_bit(copy_sign(0.0, -1.0)))
    try expect_false(sign_bit(copy_sign(-0.0, 1.0)))

    let negative_nan = copy_sign(nan, -1.0)
    try expect_true(negative_nan.is_nan())
    try expect_true(sign_bit(negative_nan))
    try expect_equal(copy_sign(infinity, negative_nan), -infinity)

test "adjacent floats cross signed zeros subnormals and infinities exactly":
    try expect_equal(next_after(1.0, 2.0), 1.0000000000000002)
    try expect_equal(next_after(1.0, 0.0), 0.9999999999999999)
    try expect_equal(next_after(0.0, 1.0), min_float)
    try expect_equal(next_after(0.0, -1.0), -min_float)
    try expect_true(sign_bit(next_after(0.0, -0.0)))
    try expect_false(sign_bit(next_after(-0.0, 0.0)))
    try expect_false(sign_bit(next_after(min_float, -1.0)))
    try expect_true(sign_bit(next_after(-min_float, 1.0)))
    try expect_equal(next_after(max_float, infinity), infinity)
    try expect_equal(next_after(infinity, 0.0), max_float)
    try expect_equal(next_after(-max_float, -infinity), -infinity)
    try expect_equal(next_after(-infinity, 0.0), -max_float)
    try expect_true(next_after(nan, 0.0).is_nan())
    try expect_true(next_after(0.0, nan).is_nan())

test "fused multiply-add rounds once and avoids intermediate overflow":
    let left = 1.0000000074505806
    let right = 0.9999999925494194
    try expect_equal(left * right - 1.0, 0.0)
    try expect_equal(fma(left, right, -1.0), -5.551115123125783e-17)
    try expect_equal(fma(max_float, 2.0, -max_float), max_float)
    try expect_true(fma(0.0, infinity, 1.0).is_nan())
    try expect_true(fma(nan, 1.0, 0.0).is_nan())

test "big integer gcd and lcm normalize signs and zero":
    for left in [-12, 0, 12]:
        for right in [-18, 0, 18]:
            let a = from_int(left)
            let b = from_int(right)
            let common = a.gcd(b)
            let multiple = a.lcm(b)
            try expect_equal(common, b.gcd(a))
            try expect_equal(multiple, b.lcm(a))
            try expect_equal(common * multiple, (a * b).abs())
            try expect_false(common.sign() < 0)
            try expect_false(multiple.sign() < 0)

    try expect_equal(from_int(-12).gcd(from_int(18)), from_int(6))
    try expect_equal(from_int(-12).lcm(from_int(18)), from_int(36))
    try expect_equal(from_int(0).gcd(from_int(0)), from_int(0))
    try expect_equal(from_int(0).lcm(from_int(0)), from_int(0))

test "big integer square root is exact and rejects negative input":
    for number in [0, 1, 2, 3, 4, 15, 16, 17, 9223372036854775807]:
        let value = from_int(number)
        let root = try value.sqrt()
        try expect_true(root * root <= value)

        let above = root + from_int(1)
        try expect_true(above * above > value)

    let invalid: BigInt!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(from_int(-1).sqrt(), invalid)

test "modular exponentiation normalizes results and validates its domain":
    try expect_equal(
        (try from_int(2).pow_mod(from_int(10), from_int(1000))), from_int(24)
    )
    try expect_equal((try from_int(-2).pow_mod(from_int(3), from_int(5))), from_int(2))
    try expect_equal((try from_int(-2).pow_mod(from_int(4), from_int(5))), from_int(1))
    try expect_equal((try from_int(0).pow_mod(from_int(0), from_int(7))), from_int(1))
    try expect_equal((try from_int(0).pow_mod(from_int(0), from_int(1))), from_int(0))

    let invalid: BigInt!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(from_int(2).pow_mod(from_int(-1), from_int(7)), invalid)
    try expect_equal(from_int(2).pow_mod(from_int(3), from_int(0)), invalid)
    try expect_equal(from_int(2).pow_mod(from_int(3), from_int(-7)), invalid)

test "big integer helpers scale from machine words to 4096-bit values":
    let one = from_int(1)

    for width in [64, 256, 1024, 4096]:
        let factor = (try one.shift_left(width)) + one
        let a = factor * from_int(35)
        let b = factor * from_int(77)
        try expect_equal(a.gcd(b), factor * from_int(7))
        try expect_equal(a.lcm(b), factor * from_int(385))

        let square = factor * factor
        try expect_equal((try square.sqrt()), factor)
        try expect_equal((try (square - one).sqrt()), factor - one)

        let modulus = (try one.shift_left(width)) - one
        try expect_equal((try from_int(2).pow_mod(from_int(width), modulus)), one)

    let exponent = try parse("184467440737095516160000000000000000000000", 10)
    try expect_equal((try from_int(2).pow_mod(exponent, from_int(7))), from_int(2))

test "modular exponentiation matches exact large odd and even modulus reference vectors":
    let base = try parse("-123456789012345678901234567891", 10)
    let exponent = from_int(12345)
    let odd = try parse("10000000000000000000000000000000000000007", 10)
    let even = try parse("340282366920938463463374607431768211456", 10)
    let odd_result = try parse("4339799581317112657124184116489215648661", 10)
    let even_result = try parse("223193219010250399600239597668322418573", 10)
    try expect_equal((try base.pow_mod(exponent, odd)), odd_result)
    try expect_equal((try base.pow_mod(exponent, even)), even_result)
