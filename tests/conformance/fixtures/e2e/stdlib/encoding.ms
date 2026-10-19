# conform: tags=control-flow,modules,stdlib-bytes,stdlib-encoding,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/encoding.ms
import {expect_equal} from "@std/testing.ms"
import {
    base64_encode,
    base64_decode,
    hex_encode,
    hex_decode,
    EncodingError,
    utf16_encode,
    utf16_decode,
    latin1_encode,
    latin1_decode,
    ascii_encode,
    ascii_decode
} from "@std/encoding.ms"
import Bytes from "@std/bytes.ms"

test "encoding known vectors and exact output limits":
    let data = Bytes([0, 255, 66])
    try expect_equal(hex_encode(data), "00ff42")
    try expect_equal((try hex_decode("00FF42", 3)), data)
    try expect_equal(base64_encode(data, url_safe: false), "AP9C")
    try expect_equal((try base64_decode("_w==", url_safe: true)), Bytes([255]))
    try expect_equal((try hex_decode("", 0)), Bytes([]))

test "encoding rejects malformed data and invalid budgets":
    for text in ["Zh==", "Zg=", "Zg==\n", "_w=="]:
        let actual = base64_decode(text, url_safe: false)
        let expected: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
        try expect_equal(actual, expected)

    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    try expect_equal(hex_decode("00ff", 1), limited)
    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidInput)
    try expect_equal(hex_decode("", -1), invalid)

test "UTF-16 encodes surrogate pairs in either byte order":
    try expect_equal(utf16_encode("a€😀"), Bytes([97, 0, 172, 32, 61, 216, 0, 222]))
    try expect_equal(utf16_encode("a", little_endian: false), Bytes([0, 97]))
    try expect_equal(try utf16_decode(Bytes([97, 0, 172, 32, 61, 216, 0, 222])), "a€😀")
    try expect_equal(try utf16_decode(Bytes([0, 97]), little_endian: false), "a")
    let invalid: Result[String, EncodingError] = error(EncodingError.InvalidData)
    try expect_equal(utf16_decode(Bytes([97])), invalid)
    try expect_equal(utf16_decode(Bytes([61, 216])), invalid)
    try expect_equal(utf16_decode(Bytes([0, 222])), invalid)
    let limited: Result[String, EncodingError] = error(EncodingError.LimitExceeded)
    try expect_equal(utf16_decode(Bytes([172, 32]), max_bytes: 2), limited)

test "Latin-1 and ASCII are strict single-byte encodings":
    try expect_equal(try latin1_encode("é"), Bytes([233]))
    try expect_equal(latin1_decode(Bytes([233, 65])), "éA")
    let invalid_encode: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    try expect_equal(latin1_encode("€"), invalid_encode)
    try expect_equal(try ascii_encode("Hi"), Bytes([72, 105]))
    try expect_equal(ascii_encode("é"), invalid_encode)
    try expect_equal(try ascii_decode(Bytes([72, 105])), "Hi")
    let invalid_decode: Result[String, EncodingError] = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(Bytes([200])), invalid_decode)
