import {expect_equal, expect_ok} from "@std/testing.ms"
import {base64_encode, base64_decode, hex_encode, hex_decode, EncodingError} from "@std/encoding.ms"
import Bytes from "@std/bytes.ms"

test "encoding known vectors and exact output limits":
    let data = Bytes([0, 255, 66])
    hex_encode(data) | try expect_equal(expected: "00ff42")
    hex_decode(text: "00FF42", max_bytes: 3) | try expect_ok | try expect_equal(
        expected: data
    )
    base64_encode(data: data, url_safe: false) | try expect_equal(expected: "AP9C")
    base64_decode(text: "_w==", url_safe: true) | try expect_ok | try expect_equal(
        expected: Bytes([255])
    )
    hex_decode(text: "", max_bytes: 0) | try expect_ok | try expect_equal(
        expected: Bytes([])
    )

test "encoding rejects malformed data and invalid budgets":
    for text in ["Zh==", "Zg=", "Zg==\n", "_w=="]:
        let actual = base64_decode(text: text, url_safe: false)
        let expected: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
        actual | try expect_equal(expected: expected)

    let limited: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    hex_decode(text: "00ff", max_bytes: 1) | try expect_equal(expected: limited)
    let invalid: Result[Bytes, EncodingError] = error(EncodingError.InvalidInput)
    hex_decode(text: "", max_bytes: -1) | try expect_equal(expected: invalid)
