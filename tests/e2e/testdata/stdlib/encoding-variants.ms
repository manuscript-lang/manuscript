import Bytes, BytesBuilder from "@std/bytes.ms"
import (
    base64_encode_unpadded,
    base64_decode_unpadded,
    base32_encode,
    base32_decode
) from "@std/data/encoding.ms"
import expect_equal from "@std/test/test.ms"

test "unpadded Base64 covers both alphabets and every tail":
    let texts = ["", "f", "fo", "foo", "foob", "fooba", "foobar"]
    let encoded = ["", "Zg", "Zm8", "Zm9v", "Zm9vYg", "Zm9vYmE", "Zm9vYmFy"]

    for index in 0..texts.length():
        for url_safe in [false, true]:
            try expect_equal(
                base64_encode_unpadded(
                    texts[index].to_bytes(), url_safe
                ),
                encoded[index]
            )
            try expect_equal(
                try base64_decode_unpadded(encoded[index], url_safe),
                texts[index].to_bytes()
            )

    let bytes = Bytes([251, 255])
    try expect_equal(base64_encode_unpadded(bytes), "+/8")
    try expect_equal(base64_encode_unpadded(bytes, true), "-_8")
    try expect_equal(try base64_decode_unpadded("-_8", true), bytes)

test "unpadded Base64 rejects padding alphabet mixing whitespace and unused bits":
    let invalid: Bytes! = error(
        Error("encoding: invalid data", kind: ErrorCategory.InvalidData)
    )
    for text in [
        "A", "AAAAA", "Zg=", "Zg==", "=Zg", "Zh", "Zm9", "Z g", "Zg\n", "Zg\r", "Zg\t",
        "é", "!!!!"
    ]:
        try expect_equal(base64_decode_unpadded(text), invalid)
    try expect_equal(base64_decode_unpadded("-_8"), invalid)
    try expect_equal(base64_decode_unpadded("+/8", true), invalid)

test "Base32 matches RFC 4648 padded and unpadded vectors":
    let texts = ["", "f", "fo", "foo", "foob", "fooba", "foobar"]
    let encoded = [
        "", "MY======", "MZXQ====", "MZXW6===", "MZXW6YQ=", "MZXW6YTB",
        "MZXW6YTBOI======"
    ]
    let raw = ["", "MY", "MZXQ", "MZXW6", "MZXW6YQ", "MZXW6YTB", "MZXW6YTBOI"]
    let hex = [
        "", "CO======", "CPNG====", "CPNMU===", "CPNMUOG=", "CPNMUOJ1",
        "CPNMUOJ1E8======"
    ]
    let hex_raw = ["", "CO", "CPNG", "CPNMU", "CPNMUOG", "CPNMUOJ1", "CPNMUOJ1E8"]

    for index in 0..texts.length():
        let bytes = texts[index].to_bytes()
        try expect_equal(base32_encode(bytes), encoded[index])
        try expect_equal(base32_encode(bytes, padded: false), raw[index])
        try expect_equal(base32_encode(bytes, true), hex[index])
        try expect_equal(base32_encode(bytes, true, false), hex_raw[index])
        try expect_equal(try base32_decode(encoded[index]), bytes)
        try expect_equal(try base32_decode(raw[index], padded: false), bytes)
        try expect_equal(try base32_decode(hex[index], true), bytes)
        try expect_equal(try base32_decode(hex_raw[index], true, false), bytes)

test "Base32 enforces exact terminal padding and uppercase alphabets":
    let invalid: Bytes! = error(
        Error("encoding: invalid data", kind: ErrorCategory.InvalidData)
    )
    for text in [
        "M", "MY", "MY=", "MY=====", "MY=======", "M======", "MZX=====", "MZXW6Y==",
        "========", "MY======MY======", "M=AAAAAA", "my======", "M0======", "M1======",
        "M8======", "M9======", "MY=====\n", "M Y=====", "éY======"
    ]:
        try expect_equal(base32_decode(text), invalid)
    for text in [
        "M", "MZX", "MZXW6Y", "MY=", "MY======", "my", "M0", "M1", "M8", "M9", "MY\r\n"
    ]:
        try expect_equal(base32_decode(text, padded: false), invalid)
    try expect_equal(base32_decode("W0======", true), invalid)
    try expect_equal(base32_decode("CO======"), invalid)

test "Base32 rejects nonzero unused bits in each tail shape":
    let invalid: Bytes! = error(
        Error("encoding: invalid data", kind: ErrorCategory.InvalidData)
    )
    for text in ["MZ======", "MZX R===", "MZXR====", "MZXW7===", "MZXW6YR="]:
        try expect_equal(base32_decode(text), invalid)
    for text in ["MZ", "MZXR", "MZXW7", "MZXW6YR"]:
        try expect_equal(base32_decode(text, padded: false), invalid)
    for text in ["CP======", "CPNH====", "CPNMV===", "CPNMUOH="]:
        try expect_equal(base32_decode(text, true), invalid)

test "encoding variants honor zero exact exceeded absent and negative limits":
    let empty = Bytes([])
    let invalid: Bytes! = error(
        Error("encoding: invalid input", kind: ErrorCategory.InvalidInput)
    )
    let limited: Bytes! = error(
        Error("encoding: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    try expect_equal(try base32_decode("", max_bytes: 0), empty)
    try expect_equal(try base64_decode_unpadded("", max_bytes: 0), empty)
    try expect_equal(try base32_decode("MY======", max_bytes: 1), "f".to_bytes())
    try expect_equal(
        try base32_decode("MY", padded: false, max_bytes: 1), "f".to_bytes()
    )
    try expect_equal(base32_decode("MY======", max_bytes: 0), limited)
    try expect_equal(base64_decode_unpadded("Zg", max_bytes: 0), limited)
    try expect_equal(try base64_decode_unpadded("Zg", max_bytes: 1), "f".to_bytes())
    try expect_equal(try base32_decode("MY======", max_bytes: none), "f".to_bytes())
    try expect_equal(try base64_decode_unpadded("Zg", max_bytes: none), "f".to_bytes())

    for text in ["", "?", "MY======"]:
        try expect_equal(base32_decode(text, max_bytes: -1), invalid)
        try expect_equal(base64_decode_unpadded(text, max_bytes: -1), invalid)

test "encoding variants honor Bytes views and cross block boundaries":
    var out = BytesBuilder()
    for value in 0..256: out.append(value.to_uint8().get(0))

    let all = out.build()

    for length in 0..256:
        let bytes = try all.slice(0, length)
        for hex in [false, true]:
            for padded in [false, true]:
                try expect_equal(
                    try base32_decode(
                        base32_encode(bytes, hex, padded), hex, padded, length
                    ),
                    bytes
                )
        for url in [false, true]:
            try expect_equal(
                try base64_decode_unpadded(
                    base64_encode_unpadded(bytes, url), url, length
                ),
                bytes
            )

    let view = try all.slice(17, 219)
    try expect_equal(try base32_decode(base32_encode(view)), view)
    try expect_equal(try base64_decode_unpadded(base64_encode_unpadded(view)), view)

test "encoding variant function values retain defaults":
    let encode = base32_encode
    let decode = base32_decode
    try expect_equal(encode("f".to_bytes()), "MY======")
    try expect_equal(try decode("MY======"), "f".to_bytes())

    let raw_encode = base64_encode_unpadded
    let raw_decode = base64_decode_unpadded
    try expect_equal(raw_encode("f".to_bytes()), "Zg")
    try expect_equal(try raw_decode("Zg"), "f".to_bytes())
