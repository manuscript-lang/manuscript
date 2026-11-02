import Bytes from "@std/bytes.ms"
import from_scalars from "@std/string.ms"
import (
    decode_first,
    decode_last,
    is_valid,
    Utf8Scalar,
    Utf8Error
) from "@std/data/utf8.ms"
import (
    expect_equal,
    expect_ok,
    expect_error,
    expect_fault,
    expect_contains
) from "@std/test/test.ms"

test "UTF8 validity checks the complete buffer without replacement":
    for data in [Bytes([]), "aé🙂e\u{301}\u{0}".to_bytes(), Bytes([239, 191, 189])]:
        is_valid(data) | try expect_equal(true)
    for data in [
        Bytes([97, 255]), Bytes([194]), Bytes([128]), Bytes([192, 128]),
        Bytes([237, 160, 128]), Bytes([244, 144, 128, 128])
    ]:
        is_valid(data) | try expect_equal(false)

fn expect_scalar(actual: Utf8Scalar!Utf8Error, value: Int, width: Int) Unit!:
    let decoded = actual | try expect_ok
    decoded.scalar | try expect_equal(value)
    return decoded.width | expect_equal(width)

test "UTF8 decodes exact scalar boundaries and widths":
    let values = [0, 127, 128, 2047, 2048, 55295, 57344, 65533, 65535, 65536, 1114111]
    let widths = [1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4]

    for index in 0..values.length():
        let bytes = from_scalars([values[index]]) | try expect_ok
        decode_first(bytes.to_bytes()) | try expect_scalar(values[index], widths[index])
        decode_last(bytes.to_bytes()) | try expect_scalar(values[index], widths[index])

test "UTF8 offsets count bytes and leave adjacent malformed bytes alone":
    let data = "aé🙂e\u{301}".to_bytes()
    decode_first(data, 1) | try expect_scalar(233, 2)
    decode_first(data, 3) | try expect_scalar(128578, 4)
    decode_last(data, 3) | try expect_scalar(233, 2)
    decode_last(data, 7) | try expect_scalar(128578, 4)
    decode_last(data, none) | try expect_scalar(769, 2)
    decode_first(Bytes([97, 255])) | try expect_scalar(97, 1)
    decode_first(Bytes([97, 226, 130])) | try expect_scalar(97, 1)
    decode_first(Bytes([194, 162, 255])) | try expect_scalar(162, 2)
    decode_last(Bytes([255, 194, 162])) | try expect_scalar(162, 2)
    decode_last("🙂é".to_bytes()) | try expect_scalar(233, 2)
    decode_first(Bytes([239, 191, 189])) | try expect_scalar(65533, 3)

test "UTF8 distinguishes incomplete prefixes from malformed encodings":
    for data in [Bytes([]), Bytes([194]), Bytes([226, 130]), Bytes([240, 144, 128])]:
        decode_first(data) | try expect_error | try expect_equal(Utf8Error.Incomplete)
        decode_last(data) | try expect_error | try expect_equal(Utf8Error.Incomplete)

    for data in [
        Bytes([128]), Bytes([192, 128]), Bytes([193, 191]), Bytes([224, 128]),
        Bytes([237, 160, 128]), Bytes([244, 144]), Bytes([245, 128, 128, 128]),
        Bytes([255])
    ]:
        decode_first(data) | try expect_error | try expect_equal(Utf8Error.InvalidData)
        decode_last(data) | try expect_error | try expect_equal(Utf8Error.InvalidData)

    decode_last(Bytes([194, 162, 128])) | try expect_error | try expect_equal(
        Utf8Error.InvalidData
    )
    decode_first("🙂".to_bytes(), 1) | try expect_error | try expect_equal(
        Utf8Error.InvalidData
    )
    decode_last("🙂".to_bytes(), 3) | try expect_error | try expect_equal(
        Utf8Error.Incomplete
    )
    decode_last(Bytes([255, 226, 130])) | try expect_error | try expect_equal(
        Utf8Error.Incomplete
    )
    decode_first(Bytes([240, 128, 128, 128])) | try expect_error | try expect_equal(
        Utf8Error.InvalidData
    )

test "UTF8 rejects invalid offsets without negative index wrapping":
    let data = "é".to_bytes()

    for offset in [-1, 3, 9223372036854775807]:
        let first_fault = fn:
            let _ignored = decode_first(data, offset)
        let last_fault = fn:
            let _ignored = decode_last(data, offset)
        expect_fault(first_fault) | try expect_ok | try expect_contains(
            "utf8.decode_first: at"
        )
        expect_fault(last_fault) | try expect_ok | try expect_contains(
            "utf8.decode_last: end"
        )

    decode_first(data, data.length()) | try expect_error | try expect_equal(
        Utf8Error.Incomplete
    )
    decode_last(data, 0) | try expect_error | try expect_equal(Utf8Error.Incomplete)

test "UTF8 supports forward and reverse walks without normalization":
    let data = "é🙂e\u{301}\u{0}".to_bytes()
    var forward = List[Int]()
    var position = 0

    while position < data.length():
        let decoded = decode_first(data, position) | try expect_ok
        forward.append(decoded.scalar)
        position = position + decoded.width

    forward | try expect_equal([233, 128578, 101, 769, 0])

    var backward = List[Int]()

    while position > 0:
        let decoded = decode_last(data, position) | try expect_ok
        backward.append(decoded.scalar)
        position = position - decoded.width

    backward | try expect_equal([0, 769, 101, 128578, 233])

    let first = decode_first
    let last = decode_last
    first(data, 0) | try expect_scalar(233, 2)
    last(data, none) | try expect_scalar(0, 1)

test "UTF8 selects a bounded prefix or suffix in large inputs":
    let fill = "x".repeat(262144) | try expect_ok
    let data = "🙂".concat(fill).concat("é").to_bytes()
    decode_first(data) | try expect_scalar(128578, 4)
    decode_last(data) | try expect_scalar(233, 2)
