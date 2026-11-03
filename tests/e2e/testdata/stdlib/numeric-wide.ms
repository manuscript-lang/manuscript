import (
    expect_equal,
    expect_true,
    expect_false,
    expect_ok,
    expect_some
) from "@std/test/test.ms"
import (
    add_with_carry,
    subtract_with_borrow,
    multiply_wide,
    divide_wide,
    remainder_wide,
    WordDivision,
    BigInt,
    from_int,
    parse,
    frexp,
    ldexp,
    modf,
    ieee_remainder,
    remainder,
    sign_bit,
    infinity,
    nan,
    min_float,
    max_float,
    min_int,
    max_int
) from "@std/math/math.ms"

fn big_word(value: UInt64) BigInt:
    return parse(value.to_string_radix(10), 10).get()

test "carry and borrow operate on unsigned words and chain across limbs":
    let largest: UInt64 = 18446744073709551615
    let zero: UInt64 = 0
    let one: UInt64 = 1
    let low = add_with_carry(largest, one)
    try expect_equal(low.sum, zero)
    try expect_true(low.carry)

    let high = add_with_carry(8, 9, low.carry)
    try expect_equal(high.sum, 18)
    try expect_false(high.carry)

    let difference = subtract_with_borrow(zero, one)
    try expect_equal(difference.difference, largest)
    try expect_true(difference.borrow)

    let high_difference = subtract_with_borrow(18, 9, difference.borrow)
    try expect_equal(high_difference.difference, 8)
    try expect_false(high_difference.borrow)
    try expect_true(add_with_carry(largest, largest, true).carry)
    try expect_equal(add_with_carry(largest, zero, true).sum, zero)
    try expect_true(subtract_with_borrow(zero, largest, true).borrow)
    try expect_equal(subtract_with_borrow(zero, largest, true).difference, zero)

test "word arithmetic matches exact BigInt references at all width boundaries":
    let values: List[UInt64] = [
        0, 1, 4294967295, 4294967296, 9223372036854775808, 18446744073709551615
    ]
    let radix = try from_int(1).shift_left(64)

    for left in values:
        for right in values:
            let a = big_word(left)
            let b = big_word(right)

            for flag in [false, true]:
                let extra = from_int(if flag: 1 else: 0)
                let sum = add_with_carry(left, right, flag)
                let exact_sum = a + b + extra
                try expect_equal(big_word(sum.sum), exact_sum % radix)
                try expect_equal(sum.carry, exact_sum >= radix)

                let difference = subtract_with_borrow(left, right, flag)
                let exact_difference = a - b - extra
                let wrapped = if exact_difference.sign() < 0: exact_difference + radix else: exact_difference.clone()
                try expect_equal(big_word(difference.difference), wrapped)
                try expect_equal(difference.borrow, exact_difference.sign() < 0)

            let product = multiply_wide(left, right)
            try expect_equal(
                big_word(product.high) * radix + big_word(product.low), a * b
            )

            for divisor in values:
                if divisor != 0:
                    let actual = try remainder_wide(left, right, divisor)
                    try expect_equal(
                        big_word(actual), (a * radix + b) % big_word(divisor)
                    )

            if left != 0:
                let division = try divide_wide(product.high, product.low, left)
                try expect_equal(division.quotient, right)
                try expect_equal(division.remainder, 0)

test "wide division distinguishes invalid divisor and quotient overflow":
    let largest: UInt64 = 18446744073709551615
    let division = try divide_wide(2, largest, 3)
    try expect_equal(division.quotient, largest)
    try expect_equal(division.remainder, 2)

    let invalid: WordDivision! = error(
        Error("number: invalid input", kind: ErrorCategory.InvalidInput)
    )
    let overflow: WordDivision! = error(
        Error("number: value out of range", kind: ErrorCategory.OutOfRange)
    )
    try expect_equal(divide_wide(0, 0, 0), invalid)
    try expect_equal(divide_wide(largest, largest, 0), invalid)
    try expect_equal(divide_wide(3, 0, 3), overflow)
    try expect_equal(divide_wide(largest, 0, largest), overflow)
    try expect_equal((try remainder_wide(3, 5, 3)), 2)
    try expect_equal((try remainder_wide(largest, largest, largest)), 0)

    let invalid_remainder: UInt64! = error(
        Error("number: invalid input", kind: ErrorCategory.InvalidInput)
    )
    try expect_equal(remainder_wide(largest, largest, 0), invalid_remainder)

test "binary float decomposition round trips normals subnormals and signed zero":
    for value in [
        0.0, -0.0, min_float, -min_float, 1.0, -1.0, 8.0, -8.0, 1e-300, 1e300, max_float
    ]:
        let parts = frexp(value)
        let rebuilt = ldexp(parts.fraction, parts.exponent)
        try expect_equal(rebuilt, value)
        try expect_equal(sign_bit(rebuilt), sign_bit(value))

        if value != 0.0:
            try expect_true(parts.fraction.abs() >= 0.5)
            try expect_true(parts.fraction.abs() < 1.0)
        else:
            try expect_equal(parts.exponent, 0)

    try expect_equal(frexp(min_float).fraction, 0.5)
    try expect_equal(frexp(min_float).exponent, -1073)
    try expect_equal(frexp(max_float).exponent, 1024)

    for value in [infinity, -infinity, nan]:
        let parts = frexp(value)
        try expect_equal(parts.exponent, 0)

        if value.is_nan():
            try expect_true(parts.fraction.is_nan())
        else:
            try expect_equal(parts.fraction, value)

test "ldexp handles full Int exponents and IEEE boundary rounding":
    try expect_equal(ldexp(0.5, 4), 8.0)
    try expect_equal(ldexp(0.5, -1073), min_float)
    try expect_equal(ldexp(0.5, -1074), 0.0)
    try expect_equal(ldexp(0.75, -1074), min_float)
    try expect_equal(ldexp(1.0, max_int), infinity)
    try expect_equal(ldexp(-1.0, max_int), -infinity)
    try expect_equal(ldexp(1.0, min_int), 0.0)
    try expect_true(sign_bit(ldexp(-1.0, min_int)))

    for exponent in [min_int, max_int]:
        try expect_true(sign_bit(ldexp(-0.0, exponent)))
        try expect_equal(ldexp(infinity, exponent), infinity)
        try expect_equal(ldexp(-infinity, exponent), -infinity)
        try expect_true(ldexp(nan, exponent).is_nan())

test "float integer and fractional parts retain signs and special values":
    let ordinary = modf(-2.75)
    try expect_equal(ordinary.integer, -2.0)
    try expect_equal(ordinary.fraction, -0.75)
    try expect_true(sign_bit(modf(-0.5).integer))
    try expect_true(sign_bit(modf(-2.0).fraction))
    try expect_true(sign_bit(modf(-0.0).integer))
    try expect_true(sign_bit(modf(-0.0).fraction))
    try expect_equal(modf(infinity).integer, infinity)
    try expect_equal(modf(infinity).fraction, 0.0)
    try expect_equal(modf(-infinity).integer, -infinity)
    try expect_true(sign_bit(modf(-infinity).fraction))
    try expect_true(modf(nan).integer.is_nan())
    try expect_true(modf(nan).fraction.is_nan())

    let tiny = modf(-min_float)
    try expect_true(sign_bit(tiny.integer))
    try expect_equal(tiny.fraction, -min_float)

test "IEEE remainder uses nearest-even quotient without changing truncating remainder":
    try expect_equal(remainder(5.0, 3.0), 2.0)
    try expect_equal(ieee_remainder(5.0, 3.0), -1.0)
    try expect_equal(ieee_remainder(5.0, 2.0), 1.0)
    try expect_equal(ieee_remainder(7.0, 2.0), -1.0)
    try expect_equal(ieee_remainder(-5.0, 2.0), -1.0)
    try expect_equal(ieee_remainder(5.0, -2.0), 1.0)
    try expect_true(sign_bit(ieee_remainder(-4.0, 2.0)))
    try expect_equal(ieee_remainder(min_float, min_float + min_float), min_float)
    try expect_equal(ieee_remainder(3.0, infinity), 3.0)
    try expect_true(sign_bit(ieee_remainder(-0.0, infinity)))
    try expect_true(ieee_remainder(infinity, 1.0).is_nan())
    try expect_true(ieee_remainder(1.0, 0.0).is_nan())
    try expect_true(ieee_remainder(nan, 1.0).is_nan())
    try expect_true(ieee_remainder(1.0, nan).is_nan())

test "modular inverse distinguishes absence invalid modulus and the unit modulus":
    from_int(271).inverse_mod(
        from_int(383)
    ) | try expect_ok | try expect_some | try expect_equal(from_int(106))
    from_int(-271).inverse_mod(
        from_int(383)
    ) | try expect_ok | try expect_some | try expect_equal(from_int(277))
    try expect_true((try from_int(6).inverse_mod(from_int(9))).is_none())
    try expect_true((try from_int(0).inverse_mod(from_int(2))).is_none())
    for number in [-5, 0, 5]:
        from_int(number).inverse_mod(
            from_int(1)
        ) | try expect_ok | try expect_some | try expect_equal(from_int(0))

    let invalid: BigInt?! = error(
        Error("big integer: invalid input", kind: ErrorCategory.InvalidInput)
    )
    try expect_equal(from_int(2).inverse_mod(from_int(0)), invalid)
    try expect_equal(from_int(2).inverse_mod(from_int(-7)), invalid)

test "modular inverse scales to 4096 bits and retains canonical residues":
    let one = from_int(1)

    for width in [64, 256, 1024, 4096]:
        let modulus = try one.shift_left(width)
        let base = modulus - one
        let inverse = (try base.inverse_mod(modulus)) | try expect_some
        try expect_equal(inverse, base)
        try expect_equal(base * inverse % modulus, one)
        (
            base.negate().inverse_mod(
                modulus
            ) | try expect_ok | try expect_some | try expect_equal(one)
        )
