import expect_equal from "@std/test/test.ms"

type RoundingCase:
    input: Int
    expected: Float

fn convert(value: Int) Float32:
    return value.to_float32()

test "integer to Float32 rounds once at binary32 midpoints":
    let cases = [
        RoundingCase(18014399583223807, 1.8014398509481984e+16),
        RoundingCase(-18014399583223807, -1.8014398509481984e+16),
        RoundingCase(18014399583223808, 1.8014398509481984e+16),
        RoundingCase(-18014399583223808, -1.8014398509481984e+16),
        RoundingCase(18014399583223809, 1.801440065696563e+16),
        RoundingCase(-18014399583223809, -1.801440065696563e+16),
        RoundingCase(18014401730707455, 1.801440065696563e+16),
        RoundingCase(-18014401730707455, -1.801440065696563e+16),
        RoundingCase(18014401730707456, 1.801440280444928e+16),
        RoundingCase(-18014401730707456, -1.801440280444928e+16),
        RoundingCase(18014401730707457, 1.801440280444928e+16),
        RoundingCase(-18014401730707457, -1.801440280444928e+16),
        RoundingCase(4611686293305294847, 4.611686018427388e+18),
        RoundingCase(-4611686293305294847, -4.611686018427388e+18),
        RoundingCase(4611686293305294848, 4.611686018427388e+18),
        RoundingCase(-4611686293305294848, -4.611686018427388e+18),
        RoundingCase(4611686293305294849, 4.611686568183202e+18),
        RoundingCase(-4611686293305294849, -4.611686568183202e+18),
        RoundingCase(4611686843061108735, 4.611686568183202e+18),
        RoundingCase(-4611686843061108735, -4.611686568183202e+18),
        RoundingCase(4611686843061108736, 4.611687117939016e+18),
        RoundingCase(-4611686843061108736, -4.611687117939016e+18),
        RoundingCase(4611686843061108737, 4.611687117939016e+18),
        RoundingCase(-4611686843061108737, -4.611687117939016e+18),
        RoundingCase(0, 0.0), RoundingCase(16777217, 16777216.0),
        RoundingCase(9223372036854775807, 9.223372036854776e+18),
        RoundingCase(-9223372036854775808, -9.223372036854776e+18)
    ]

    for item in cases:
        try expect_equal(convert(item.input).to_float(), item.expected)

        let bound = item.input.to_float32
        try expect_equal(bound().to_float(), item.expected)

test "constant integer to Float32 rounds directly":
    try expect_equal(4611686293305294849.to_float32().to_float(), 4611686568183201792.0)
    try expect_equal(
        (-4611686293305294849).to_float32().to_float(), -4611686568183201792.0
    )

test "smaller integer conversions preserve their value":
    let small: Int8 = -128
    let medium: Int16 = 32767
    let large: Int32 = 2147483647
    try expect_equal(small.to_float32().to_float(), -128.0)
    try expect_equal(medium.to_float32().to_float(), 32767.0)
    try expect_equal(large.to_float32().to_float(), 2147483648.0)
