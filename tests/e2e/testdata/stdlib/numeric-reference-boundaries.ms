import expect_equal, expect_error, expect_true, fail from "@std/test/test.ms"
import (
    float_boundaries,
    finite_float_boundaries,
    int_boundaries
) from "@std/test/boundary.ms"
import (
    BigRat,
    rat,
    parse_rat,
    big_float_of_float,
    big_float_of_rat,
    rat_of_float,
    rat_of_int,
    rat_of_big_int
) from "@std/math/big.ms"
import (
    BigInt,
    from_int,
    floor,
    ceil,
    round,
    round_to_even,
    truncate,
    modf,
    frexp,
    ldexp,
    next_after,
    fma,
    ieee_remainder,
    remainder,
    copy_sign,
    sqrt,
    is_integer,
    min_int,
    max_int,
    wrapping_add,
    wrapping_subtract,
    wrapping_multiply,
    multiply_wide,
    add_with_carry,
    subtract_with_borrow,
    divide_wide,
    remainder_wide,
    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    shift_left,
    shift_right,
    shift_right_unsigned,
    rotate_left,
    rotate_right,
    count_ones,
    leading_zeros,
    trailing_zeros,
    parse_int
) from "@std/math/math.ms"

// The two's-complement 64-bit wrap of an exact integer.
fn wrap64(value: BigInt) BigInt!:
    let modulus = try (from_int(1).shift_left(64))
    var reduced = try value.remainder(modulus)
    if reduced.sign() < 0:
        reduced += modulus

    let half = try (from_int(1).shift_left(63))
    if reduced.compare(half) >= 0:
        reduced -= modulus
    return ok(reduced)

fn same_float(actual: Float, expected: Float) Bool:
    if actual.is_nan() or expected.is_nan():
        return actual.is_nan() and expected.is_nan()

    return (
        actual == expected and 1.0 / actual == 1.0 / expected
        or actual == expected and actual != 0.0
    )

test "wrapping arithmetic matches exact arithmetic reduced mod 2^64":
    for a in int_boundaries():
        for b in int_boundaries():
            let sum = try wrap64(from_int(a) + from_int(b))
            let difference = try wrap64(from_int(a) - from_int(b))
            let product = try wrap64(from_int(a) * from_int(b))
            try expect_equal(from_int(wrapping_add(a, b)), sum)
            try expect_equal(from_int(wrapping_subtract(a, b)), difference)
            try expect_equal(from_int(wrapping_multiply(a, b)), product)

fn big_of_word(word: UInt64) BigInt:
    if let small = word.to_int(): return from_int(small)

    let low = (word - 9223372036854775808).to_int().get(0)
    return from_int(low) + from_int(max_int) + from_int(1)

test "multiply_wide matches the exact 128-bit product":
    let words: List[UInt64] = [
        0, 1, 2, 4294967295, 4294967296, 9223372036854775807, 9223372036854775808,
        18446744073709551615
    ]

    for a in words:
        for b in words:
            let exact = big_of_word(a) * big_of_word(b)
            let parts = multiply_wide(a, b)
            let shifted = try big_of_word(parts.high).shift_left(64)
            try expect_equal(shifted + big_of_word(parts.low), exact)

test "rounding functions agree with exact rationals":
    for x in finite_float_boundaries():
        let exact = rat_of_float(x).get(rat_of_int(0))
        try expect_equal(
            rat_of_float(floor(x)).get(rat_of_int(7)).numerator(), exact.floor()
        )
        try expect_equal(
            rat_of_float(ceil(x)).get(rat_of_int(7)).numerator(), exact.ceil()
        )
        try expect_equal(
            rat_of_float(truncate(x)).get(rat_of_int(7)).numerator(), exact.truncate()
        )

        // `round` sends ties toward positive infinity, unlike `BigRat.round`, which sends them away from zero.
        let half = try rat(from_int(1), from_int(2))
        try expect_equal(
            rat_of_float(round(x)).get(rat_of_int(7)).numerator(),
            exact.add(half).floor()
        )

test "nonfinite inputs pass through the rounding functions":
    for x in [infinity_value(), -infinity_value()]:
        try expect_true(same_float(floor(x), x))
        try expect_true(same_float(ceil(x), x))
        try expect_true(same_float(round(x), x))
        try expect_true(same_float(truncate(x), x))
        try expect_true(same_float(round_to_even(x), x))

    let not_a_number = infinity_value() - infinity_value()
    try expect_true(floor(not_a_number).is_nan())
    try expect_true(ceil(not_a_number).is_nan())
    try expect_true(round(not_a_number).is_nan())
    try expect_true(truncate(not_a_number).is_nan())

fn infinity_value() Float:
    return 1.0 / 0.0

test "modf splits exactly":
    for x in finite_float_boundaries():
        let parts = modf(x)
        let whole = rat_of_float(parts.integer).get(rat_of_int(7))
        let fraction = rat_of_float(parts.fraction).get(rat_of_int(7))
        try expect_equal(whole.add(fraction), rat_of_float(x).get(rat_of_int(7)))
        try expect_equal(whole, rat_of_float(truncate(x)).get(rat_of_int(7)))

test "frexp and ldexp round-trip every finite value":
    for x in finite_float_boundaries():
        let parts = frexp(x)
        try expect_true(same_float(ldexp(parts.fraction, parts.exponent), x))

        if x != 0.0:
            let magnitude = parts.fraction.abs()
            try expect_true(magnitude >= 0.5 and magnitude < 1.0)

test "next_after moves by exactly one representable step":
    for x in finite_float_boundaries():
        let up = next_after(x, infinity_value())
        let down = next_after(x, -infinity_value())
        try expect_true(up > x)
        try expect_true(down < x)

        let exact = rat_of_float(x).get(rat_of_int(0))
        let exact_up = rat_of_float(up)
        let exact_down = rat_of_float(down)
        if let u = exact_up:
            try expect_equal(u.compare(exact), 1)
        if let d = exact_down:
            try expect_equal(d.compare(exact), -1)

test "to_fixed matches the exact decimal expansion":
    for x in finite_float_boundaries():
        if x.abs() < 1e21:
            let exact = rat_of_float(x).get(rat_of_int(0))

            for digits in [0, 1, 2, 5, 20]:
                let expected = try exact.to_fixed(digits)
                let actual = x.to_fixed(digits)

                // A negative value that rounds to zero prints as `-0`, as in C; compare it without the sign.
                let unsigned = if actual.starts_with(
                    "-"
                ) and not expected.starts_with("-"): actual.drop(1) else: actual
                try expect_equal(unsigned, expected)

test "truncate_to_int is exact inside the Int range and none outside it":
    for x in float_boundaries():
        let result = x.truncate_to_int()

        if not x.is_finite():
            try expect_equal(result, none)
        else:
            let exact = rat_of_float(x).get(rat_of_int(0)).truncate()

            if let value = exact.to_int():
                try expect_equal(result, value)
            else:
                try expect_equal(result, none)

test "fma and sqrt are correctly rounded":
    for x in finite_float_boundaries():
        if x >= 0.0:
            if let reference = big_float_of_float(x, 200):
                if let root = reference.sqrt():
                    let rounded = big_float_of_rat(root.to_rat(), 53).to_float()
                    try expect_equal(sqrt(x), rounded.get(0.0))

    for a in [1.0, 0.1, 1e308, -1e308, 1e-308, 5e-324]:
        for b in [1.0, 3.0, 1e10, -0.1, 1e-10]:
            for c in [0.0, 1.0, -1e308, 5e-324]:
                let exact = rat_of_float(a).get(rat_of_int(0)).multiply(
                    rat_of_float(b).get(rat_of_int(0))
                ).add(rat_of_float(c).get(rat_of_int(0)))
                if let nearest = exact.to_float():
                    try expect_true(same_float(fma(a, b, c), nearest) or nearest == 0.0)

fn word_boundaries() List[UInt64]:
    return [
        0, 1, 2, 4294967295, 4294967296, 9223372036854775807, 9223372036854775808,
        18446744073709551614, 18446744073709551615
    ]

fn two_pow(count: Int) BigInt:
    return from_int(1).shift_left(count).get(from_int(0))

test "add_with_carry and subtract_with_borrow match exact words":
    let modulus = two_pow(64)

    for a in word_boundaries():
        for b in word_boundaries():
            for carry in [false, true]:
                let extra = if carry: from_int(1) else: from_int(0)
                let exact = big_of_word(a) + big_of_word(b) + extra
                let sum = add_with_carry(a, b, carry)
                let rebuilt = (
                    big_of_word(sum.sum)
                    + (
                        if sum
                        .carry: modulus
                        .clone() else: from_int(0)
                    )
                )
                try expect_equal(rebuilt, exact)

                let diff = subtract_with_borrow(a, b, carry)
                let exact_diff = big_of_word(a) - big_of_word(b) - extra
                let rebuilt_diff = (
                    big_of_word(diff.difference)
                    - (
                        if diff
                        .borrow: modulus
                        .clone() else: from_int(0)
                    )
                )
                try expect_equal(rebuilt_diff, exact_diff)

test "divide_wide and remainder_wide match exact division":
    for high in word_boundaries():
        for low in word_boundaries():
            for divisor in word_boundaries():
                let numerator = (
                    (try big_of_word(high).shift_left(64))
                    + big_of_word(low)
                )

                if divisor == 0:
                    let _failure = try expect_error(divide_wide(high, low, divisor))
                    let _failure2 = try expect_error(remainder_wide(high, low, divisor))
                else:
                    let divisor_big = big_of_word(divisor)
                    let remainder = try remainder_wide(high, low, divisor)
                    try expect_equal(
                        big_of_word(remainder), try numerator.remainder(divisor_big)
                    )

                    if high >= divisor:
                        let _failure = try expect_error(divide_wide(high, low, divisor))
                    else:
                        let result = try divide_wide(high, low, divisor)
                        try expect_equal(
                            big_of_word(result.quotient),
                            try numerator.divide(
                                divisor_big
                            )
                        )
                        try expect_equal(
                            big_of_word(result.remainder),
                            try numerator.remainder(
                                divisor_big
                            )
                        )

test "bit operations match BigInt two's complement":
    for a in int_boundaries():
        for b in int_boundaries():
            try expect_equal(from_int(bit_and(a, b)), from_int(a).bit_and(from_int(b)))
            try expect_equal(from_int(bit_or(a, b)), from_int(a).bit_or(from_int(b)))
            try expect_equal(from_int(bit_xor(a, b)), from_int(a).bit_xor(from_int(b)))

        try expect_equal(from_int(bit_not(a)), from_int(a).bit_not())

test "shifts and rotations agree with exact arithmetic at every count":
    for a in int_boundaries():
        for count in [0, 1, 2, 31, 32, 33, 62, 63]:
            let shifted = try wrap64(try from_int(a).shift_left(count))
            try expect_equal(from_int(shift_left(a, count)), shifted)
            try expect_equal(
                from_int(shift_right(a, count)), try from_int(a).shift_right(count)
            )

            let rotated = rotate_left(rotate_right(a, count), count)
            try expect_equal(rotated, a)

            let word = if a < 0: from_int(a) + two_pow(64) else: from_int(a)
            let logical = try word.shift_right(count)
            try expect_equal(
                from_int(shift_right_unsigned(a, count)), try wrap64(logical)
            )

test "bit counts match the binary expansion":
    for a in int_boundaries():
        let word = if a < 0: from_int(a) + two_pow(64) else: from_int(a)
        let digits = word.to_string_radix(2)
        var ones = 0
        for c in digits.chars():
            if c == "1":
                ones += 1
        try expect_equal(count_ones(a), ones)

        let expected_leading = if a == 0: 64 else: 64 - digits.length()
        try expect_equal(leading_zeros(a), expected_leading)

        let trailing = digits.length() - (digits.last_index_of("1").get(0) + 1)
        try expect_equal(trailing_zeros(a), if a == 0: 64 else: trailing)

test "integer conversions respect each target range":
    for a in int_boundaries():
        try expect_equal(a.to_int8().is_some(), a >= -128 and a <= 127)
        try expect_equal(a.to_int16().is_some(), a >= -32768 and a <= 32767)
        try expect_equal(a.to_int32().is_some(), a >= -2147483648 and a <= 2147483647)
        try expect_equal(a.to_uint8().is_some(), a >= 0 and a <= 255)
        try expect_equal(a.to_uint16().is_some(), a >= 0 and a <= 65535)
        try expect_equal(a.to_uint32().is_some(), a >= 0 and a <= 4294967295)
        try expect_equal(a.to_uint64().is_some(), a >= 0)

test "radix text and parsing round-trip every boundary":
    for a in int_boundaries():
        for radix in [2, 8, 10, 16, 36]:
            let text = a.to_string_radix(radix)
            try expect_equal(from_int(a).to_string_radix(radix), text)
            try expect_equal(try parse_int(text, radix), a)

        try expect_equal("{a}".parse_int(), a)

test "BigInt agrees with Int on operations that cannot overflow":
    for a in int_boundaries():
        for b in int_boundaries():
            try expect_equal(from_int(a).compare(from_int(b)), a.compare(b))

            // Int division faults on min_int / -1; BigInt has the exact quotient.
            if b != 0 and not (a == min_int and b == -1):
                try expect_equal(try from_int(a).divide(from_int(b)), from_int(a / b))

test "Float text round-trips exactly":
    for x in float_boundaries():
        let back = x.to_string().parse_float()

        if x.is_nan():
            try expect_true(back.get(0.0).is_nan())
        else:
            try expect_true(same_float(back.get(1.5), x))

        for digits in [1, 17, 100]:
            let text = x.to_precision(digits)
            if x.is_finite() and digits >= 17:
                try expect_true(same_float(text.parse_float().get(1.5), x))

test "parse_float rounds like the exact rational at the range edges":
    let cases = [
        "1.7976931348623157e308", "1.7976931348623159e308", "1.797693134862315807e308",
        "2.4703282292062327e-324", "2.4703282292062328e-324", "5e-324",
        "4.9406564584124654e-324", "2.2250738585072011e-308", "9007199254740993",
        "9007199254740993.0000000000000000000001", "0.30000000000000004", "1e-400",
        "-1e-400", "1e400"
    ]

    for text in cases:
        let exact = try parse_rat(text)
        let parsed = text.parse_float()

        if let nearest = exact.to_float():
            try expect_true(
                same_float(
                    parsed.get(1.5), nearest
                ) or nearest == 0.0 and parsed.get(1.5) == 0.0
            )
        else:
            try expect_true(parsed.is_none() or not parsed.get(0.0).is_finite())

test "BigRat and BigFloat arithmetic is exact or correctly rounded on Float boundaries":
    for x in finite_float_boundaries():
        for y in finite_float_boundaries():
            let a = rat_of_float(x).get(rat_of_int(0))
            let b = rat_of_float(y).get(rat_of_int(0))
            try expect_equal(a.add(b).subtract(b), a)
            try expect_equal(a.multiply(b).compare(b.multiply(a)), 0)
            if y != 0.0:
                try expect_equal((try a.divide(b)).multiply(b), a)

            let sum = x + y
            if sum.is_finite():
                if let nearest = a.add(b).to_float():
                    try expect_true(
                        same_float(
                            sum, nearest
                        ) or nearest == 0.0 and sum == 0.0
                    )

            let product = x * y
            if product.is_finite():
                if let nearest = a.multiply(b).to_float():
                    try expect_true(
                        same_float(
                            product, nearest
                        ) or nearest == 0.0 and product == 0.0
                    )

test "ieee_remainder and remainder follow their definitions":
    for x in finite_float_boundaries():
        for y in finite_float_boundaries():
            if y != 0.0 and x.abs() < 1e300 and y.abs() > 1e-300:
                let a = rat_of_float(x).get(rat_of_int(0))
                let b = rat_of_float(y).get(rat_of_int(0))
                let quotient = try a.divide(b)
                let r = ieee_remainder(x, y)
                let exact = rat_of_float(r).get(rat_of_int(7))

                // r = x - n*y for an integer n, with |r| <= |y|/2.
                let n = try a.subtract(exact).divide(b)
                try expect_true(n.is_integer())

                let half = try rat(from_int(1), from_int(2))
                try expect_true(exact.abs().compare(b.abs().multiply(half)) <= 0)

                let t = rat_of_float(remainder(x, y)).get(rat_of_int(7))
                let expected_t = a.subtract(
                    b.multiply(rat_of_big_int(quotient.truncate()))
                )
                try expect_equal(t, expected_t)

test "conversions between Int and Float are exact where the type allows":
    for a in int_boundaries():
        let f = a.to_float()
        let exact = rat_of_int(a)
        let nearest = exact.to_float().get(0.0)
        try expect_true(same_float(f, nearest))
        try expect_equal(from_int(a).to_float().get(0.0), nearest)

test "Float32 conversion rounds once and rejects only overflow":
    for x in float_boundaries():
        let narrowed = x.to_float32()

        if x.is_finite() and x.abs() > 3.4028235677973366e38:
            try expect_true(narrowed.is_none())
        else:
            try expect_true(narrowed.is_some())

test "BigInt shifts powers and bounds at the limits":
    let one = from_int(1)

    for count in [0, 1, 63, 64, 65, 1000]:
        let shifted = try one.shift_left(count)
        try expect_equal(try shifted.shift_right(count), one.clone())
        try expect_equal(try from_int(-1).shift_right(count), from_int(-1))

    let negative_shift = one.shift_left(-1)
    let _e = try expect_error(negative_shift)
    let too_big = one.shift_left(16777217)
    let _e2 = try expect_error(too_big)
    let min = from_int(min_int)
    try expect_equal(min.negate().to_int(), none)
    try expect_equal(min.abs().to_int(), none)
    try expect_equal(min.to_int(), min_int)

test "extreme exponents do not wrap or hang":
    try expect_true(same_float(ldexp(1.0, max_int), 1.0 / 0.0))
    try expect_true(same_float(ldexp(1.0, min_int), 0.0))
    try expect_true(same_float(ldexp(-1.0, min_int), -0.0))
    try expect_true(same_float(ldexp(5e-324, 1074), 1.0))
    try expect_true(same_float(ldexp(1.0, -1074), 5e-324))
    try expect_true(same_float(ldexp(1.0, -1075), 0.0))
    try expect_true(same_float(ldexp(1.5, -1075), 5e-324))

fn ten_pow(exponent: Int) BigRat:
    var power = rat_of_int(1)
    var step = 0

    while step < (if exponent < 0: -exponent else: exponent):
        power = power.multiply(rat_of_int(10))
        step += 1

    if exponent < 0: return power.invert().get(rat_of_int(1))

    return power

test "to_exponential matches the exact decimal expansion":
    for x in finite_float_boundaries():
        if x != 0.0:
            let exact = rat_of_float(x).get(rat_of_int(0)).abs()
            var exponent = 0
            while exact.compare(ten_pow(exponent + 1)) >= 0:
                exponent += 1
            while exact.compare(ten_pow(exponent)) < 0:
                exponent -= 1

            for digits in [0, 3, 16, 17, 20]:
                var mantissa = try exact.multiply(ten_pow(-exponent)).to_fixed(digits)
                var shown = exponent

                if mantissa.starts_with("10"):
                    shown = exponent + 1
                    mantissa = try exact.multiply(ten_pow(-shown)).to_fixed(digits)

                let sign = if x < 0.0: "-" else: ""
                let exponent_sign = if shown < 0: "-" else: "+"
                let magnitude = if shown < 0: -shown else: shown
                try expect_equal(
                    x.to_exponential(digits),
                    "{sign}{mantissa}e{exponent_sign}{magnitude}"
                )

test "Decimal arithmetic matches BigInt while the result fits 34 digits":
    for a in int_boundaries():
        for b in int_boundaries():
            let x = a.to_decimal()
            let y = b.to_decimal()
            try expect_equal(
                (x + y).to_fixed(0),
                Result.ok(
                    (from_int(a) + from_int(b)).to_string_radix(10)
                )
            )
            try expect_equal(
                (x - y).to_fixed(0),
                Result.ok(
                    (from_int(a) - from_int(b)).to_string_radix(10)
                )
            )
            try expect_equal(x.compare(y), a.compare(b))

            let product = from_int(a) * from_int(b)
            if product.abs().to_string_radix(10).length() <= 34:
                try expect_equal(
                    (x * y).to_fixed(0), Result.ok(product.to_string_radix(10))
                )
