import {expect_equal} from "@std/testing.ms"
import {base64_encode, base64_decode, hex_encode, hex_decode, EncodingError} from "@std/encoding.ms"
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
