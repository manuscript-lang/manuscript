from "@std/testing.ms" import expect_equal, expect_contains, expect_fault
from "@std/bytes.ms" import Bytes, BytesBuilder, BinaryError

test "integers round-trip in both byte orders":
    var out = BytesBuilder()
    out.append_int8(-2)
    out.append_int16_le(-32768)
    out.append_int16_be(258)
    out.append_uint16_le(65535)
    out.append_uint16_be(258)
    out.append_int32_le(-2147483648)
    out.append_int32_be(16909060)
    out.append_uint32_le(4294967295)
    out.append_uint32_be(1)
    out.append_int64_le(-9223372036854775808)
    out.append_int64_be(9223372036854775807)

    let data = out.build()
    try expect_equal((try data.int8(0)).to_int(), -2)
    try expect_equal((try data.int16_le(1)).to_int(), -32768)
    try expect_equal((try data.int16_be(3)).to_int(), 258)
    try expect_equal(try data.uint16_le(5), 65535)
    try expect_equal(try data.uint16_be(7), 258)
    try expect_equal((try data.int32_le(9)).to_int(), -2147483648)
    try expect_equal((try data.int32_be(13)).to_int(), 16909060)
    try expect_equal(try data.uint32_le(17), 4294967295)
    try expect_equal(try data.uint32_be(21), 1)
    try expect_equal(try data.int64_le(25), -9223372036854775808)
    try expect_equal(try data.int64_be(33), 9223372036854775807)
    try expect_equal(data.length(), 41)

test "byte order and unsigned reads follow the bytes":
    let data = Bytes([1, 2, 255, 254])
    try expect_equal(try data.uint8(2), 255)
    try expect_equal((try data.int8(2)).to_int(), -1)
    try expect_equal((try data.int16_le(0)).to_int(), 513)
    try expect_equal((try data.int16_be(0)).to_int(), 258)
    try expect_equal(try data.uint16_be(2), 65534)
    try expect_equal((try data.int32_le(0)).to_int(), -16842239)
    try expect_equal(try data.uint32_be(0), 16973822)

test "floats round-trip in both byte orders":
    var out = BytesBuilder()
    out.append_float32_le(1.5)
    out.append_float32_be(-2.25)
    out.append_float64_le(-1.25)
    out.append_float64_be(3.5)

    let data = out.build()
    try expect_equal((try data.float32_le(0)).to_float(), 1.5)
    try expect_equal((try data.float32_be(4)).to_float(), -2.25)
    try expect_equal(try data.float64_le(8), -1.25)
    try expect_equal(try data.float64_be(16), 3.5)

test "append_bytes appends many and append one":
    var out = BytesBuilder()
    out.append(7)
    out.append_bytes(Bytes([1, 2]))
    out.append_uint16_be(772)
    try expect_equal(out.build(), Bytes([7, 1, 2, 3, 4]))

test "reads past the end or before the start are out of range":
    let range_error: Result[Int, BinaryError] = error(BinaryError.OutOfRange)
    try expect_equal(Bytes([0]).uint8(-1), range_error)
    try expect_equal(Bytes([0]).uint8(1), range_error)
    try expect_equal(Bytes([0, 0, 0]).uint32_le(0), range_error)
    try expect_equal(Bytes([0, 0, 0, 0]).uint32_le(1), range_error)
    try expect_equal(Bytes([]).uint8(0), range_error)
    try expect_equal(Bytes([0, 0, 0, 0]).uint32_le(9223372036854775807), range_error)

test "unsigned appends fault outside their range":
    let message = try expect_fault(
        lambda:
            var out = BytesBuilder()
            out.append_uint16_le(65536)
    )

    message | try expect_contains("append_uint16_le")

    let negative = try expect_fault(
        lambda:
            var out = BytesBuilder()
            out.append_uint32_be(-1)
    )

    negative | try expect_contains("append_uint32_be")
