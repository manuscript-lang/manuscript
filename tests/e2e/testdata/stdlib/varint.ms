import expect_equal, expect_true from "@std/test/test.ms"
import Bytes, BytesBuilder, BinaryError, VarintError from "@std/bytes.ms"

fn unsigned(value: UInt64) Bytes:
    var out = BytesBuilder()
    out.append_uvarint(value)
    return out.build()

fn signed(value: Int) Bytes:
    var out = BytesBuilder()
    out.append_varint(value)
    return out.build()

fn expect_varint_error(data: Bytes, at: Int, expected: VarintError) Unit!:
    let unsigned_result = data.uvarint(at)
    try expect_true(unsigned_result.is_error())
    try expect_equal(unsigned_result.err(), expected)

    let signed_result = data.varint(at)
    try expect_true(signed_result.is_error())
    try expect_equal(signed_result.err(), expected)
    return ok(unit)

test "unsigned varints have base-128 wire encodings":
    try expect_equal(unsigned(0), Bytes([0]))
    try expect_equal(unsigned(1), Bytes([1]))
    try expect_equal(unsigned(127), Bytes([127]))
    try expect_equal(unsigned(128), Bytes([128, 1]))
    try expect_equal(unsigned(255), Bytes([255, 1]))
    try expect_equal(unsigned(300), Bytes([172, 2]))
    try expect_equal(unsigned(16383), Bytes([255, 127]))
    try expect_equal(unsigned(16384), Bytes([128, 128, 1]))
    try expect_equal(
        unsigned(18446744073709551615),
        Bytes([255, 255, 255, 255, 255, 255, 255, 255, 255, 1])
    )

test "signed varints use zigzag including both extrema":
    try expect_equal(signed(0), Bytes([0]))
    try expect_equal(signed(-1), Bytes([1]))
    try expect_equal(signed(1), Bytes([2]))
    try expect_equal(signed(-2), Bytes([3]))
    try expect_equal(signed(63), Bytes([126]))
    try expect_equal(signed(-64), Bytes([127]))
    try expect_equal(signed(64), Bytes([128, 1]))
    try expect_equal(signed(-65), Bytes([129, 1]))
    try expect_equal(
        signed(9223372036854775807),
        Bytes([254, 255, 255, 255, 255, 255, 255, 255, 255, 1])
    )
    try expect_equal(
        signed(-9223372036854775808),
        Bytes([255, 255, 255, 255, 255, 255, 255, 255, 255, 1])
    )

test "unsigned varints round trip every length and group boundary":
    let values: List[UInt64] = [
        0, 1, 126, 127, 128, 129, 255, 300, 16383, 16384, 2097151, 2097152, 268435455,
        268435456, 34359738367, 34359738368, 4398046511103, 4398046511104,
        562949953421311, 562949953421312, 72057594037927935, 72057594037927936,
        9223372036854775807, 9223372036854775808, 18446744073709551615
    ]

    for value in values:
        let data = unsigned(value)
        let decoded = try data.uvarint(0)
        try expect_equal(decoded.value, value)
        try expect_equal(decoded.next_offset, data.length())

    var value: UInt64 = 1

    for bit in 0..64:
        try expect_equal((try unsigned(value).uvarint(0)).value, value)
        try expect_equal((try unsigned(value - 1).uvarint(0)).value, value - 1)
        if value < 9223372036854775808:
            value *= 2

test "signed varints round trip common values and extrema":
    for value in [
        -9223372036854775808, -9223372036854775807, -65536, -16384, -128, -65, -64, -1,
        0, 1, 63, 64, 127, 128, 16384, 65536, 9223372036854775807
    ]:
        let data = signed(value)
        let decoded = try data.varint(0)
        try expect_equal(decoded.value, value)
        try expect_equal(decoded.next_offset, data.length())

    for value in - 512..513:
        try expect_equal((try signed(value).varint(0)).value, value)

test "varint offsets chain through trailing bytes and slices":
    var out = BytesBuilder()
    out.append(99)
    out.append_uvarint(300)
    out.append_varint(-65)
    out.append_uvarint(18446744073709551615)
    out.append(77)

    let data = out.build()
    let first = try data.uvarint(1)
    try expect_equal(first.value, 300)
    try expect_equal(first.next_offset, 3)

    let second = try data.varint(first.next_offset)
    try expect_equal(second.value, -65)
    try expect_equal(second.next_offset, 5)

    let third = try data.uvarint(second.next_offset)
    try expect_equal(third.value, 18446744073709551615)
    try expect_equal(third.next_offset, 15)
    try expect_equal(data.get(third.next_offset), 77)

    let view = try data.slice(1, 15)
    let view_first = try view.uvarint(0)
    try expect_equal(view_first.value, 300)
    try expect_equal(view_first.next_offset, 2)

    let view_second = try view.varint(view_first.next_offset)
    try expect_equal(view_second.value, -65)
    try expect_equal(view_second.next_offset, 4)
    try expect_equal(
        (try view.uvarint(view_second.next_offset)).next_offset, view.length()
    )

test "each proper prefix of a minimal multibyte varint is incomplete":
    let values: List[UInt64] = [
        128, 16384, 2097152, 268435456, 34359738368, 4398046511104, 562949953421312,
        72057594037927936, 9223372036854775808, 18446744073709551615
    ]

    for value in values:
        let data = unsigned(value)
        for end in 0..data.length():
            try expect_varint_error(try data.slice(0, end), 0, VarintError.Incomplete)

        let prefixed = Bytes([99]).concat(data)
        for end in 1..prefixed.length():
            try expect_varint_error(
                try prefixed.slice(0, end), 1, VarintError.Incomplete
            )

test "varint offset errors are distinct from missing input":
    let data = Bytes([0, 1])
    for at in [-9223372036854775808, -1, 3, 9223372036854775807]:
        try expect_varint_error(data, at, VarintError.InvalidOffset)
    try expect_varint_error(data, data.length(), VarintError.Incomplete)
    try expect_varint_error(Bytes([]), 0, VarintError.Incomplete)

test "the tenth byte can only be zero or one":
    let prefix = Bytes([128, 128, 128, 128, 128, 128, 128, 128, 128])

    for byte in 2..256:
        let data = prefix.concat(Bytes([byte.to_uint8().get(0)]))
        try expect_varint_error(data, 0, VarintError.Overflow)
        try expect_varint_error(data.concat(Bytes([0])), 0, VarintError.Overflow)

    for byte in 0..2:
        let decoded = try prefix.concat(Bytes([byte.to_uint8().get(0)])).uvarint(0)
        let expected: UInt64 = if byte == 0: 0 else: 9223372036854775808
        try expect_equal(decoded.value, expected)
        try expect_equal(decoded.next_offset, 10)

test "continuation-only data stops at the representation bound":
    var out = BytesBuilder()

    for length in 0..10:
        let prefix = out.drain()
        try expect_varint_error(prefix, 0, VarintError.Incomplete)
        out.append_bytes(prefix)
        out.append(128)

    let ten = out.build()
    try expect_varint_error(ten, 0, VarintError.Overflow)
    try expect_varint_error(ten.concat(Bytes([0])), 0, VarintError.Overflow)

test "nonminimal encodings are accepted and preserve the next offset":
    let zero = try Bytes([128, 0, 255]).uvarint(0)
    try expect_equal(zero.value, 0)
    try expect_equal(zero.next_offset, 2)

    let negative = try Bytes([129, 128, 0, 255]).varint(0)
    try expect_equal(negative.value, -1)
    try expect_equal(negative.next_offset, 3)

test "unsigned fixed-width codecs cover the entire UInt64 range":
    let values: List[UInt64] = [
        0, 1, 255, 256, 4294967295, 4294967296, 9223372036854775807,
        9223372036854775808, 18446744073709551615
    ]

    for value in values:
        var out = BytesBuilder()
        out.append(99)
        out.append_uint64_le(value)
        out.append_uint64_be(value)
        out.append(77)

        let data = out.build()
        try expect_equal(try data.uint64_le(1), value)
        try expect_equal(try data.uint64_be(9), value)

        let view = try data.slice(1, 17)
        try expect_equal(try view.uint64_le(0), value)
        try expect_equal(try view.uint64_be(8), value)

    var out = BytesBuilder()
    out.append_uint64_le(18364758544493064720)
    out.append_uint64_be(18364758544493064720)
    try expect_equal(
        out.build(),
        Bytes(
            [
                16, 50, 84, 118, 152, 186, 220, 254, 254, 220, 186, 152, 118, 84, 50, 16
            ]
        )
    )

test "unsigned fixed-width reads reject missing bytes and extreme offsets":
    let expected: UInt64!BinaryError = error(BinaryError.OutOfRange)
    let data = Bytes([0, 0, 0, 0, 0, 0, 0, 0])

    for at in [-9223372036854775808, -1, 1, 8, 9223372036854775807]:
        try expect_equal(data.uint64_le(at), expected)
        try expect_equal(data.uint64_be(at), expected)

    for end in 0..8:
        let short = try data.slice(0, end)
        try expect_equal(short.uint64_le(0), expected)
        try expect_equal(short.uint64_be(0), expected)

test "varint diagnostics describe the error without echoing input":
    try expect_equal(
        VarintError.InvalidOffset.message(), "binary: invalid varint offset"
    )
    try expect_equal(VarintError.Incomplete.message(), "binary: incomplete varint")
    try expect_equal(VarintError.Overflow.message(), "binary: varint overflows 64 bits")
