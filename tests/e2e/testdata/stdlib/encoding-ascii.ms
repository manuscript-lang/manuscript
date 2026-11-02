import ascii_decode from "@std/data/encoding.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import from_scalars from "@std/string.ms"
import expect_equal from "@std/test/test.ms"

test "ASCII decoding preserves every seven-bit byte including NUL":
    var raw = BytesBuilder()
    var scalars = List[Int]()

    for scalar in 0..128:
        raw.append(scalar.to_uint8().get(0))
        scalars.append(scalar)

    try expect_equal(try ascii_decode(raw.build()), try from_scalars(scalars))
    try expect_equal(try ascii_decode(Bytes([])), "")

    let view = try "éASCII\u{0}é".to_bytes().slice(2, 8)
    try expect_equal(try ascii_decode(view), "ASCII\u{0}")
    try expect_equal(try ascii_decode("a\u{0}b\u{7f}".to_bytes()), "a\u{0}b\u{7f}")

test "ASCII decoding rejects every high byte at either end":
    let expected: String! = error(
        Error("encoding: invalid data", kind: ErrorCategory.InvalidData)
    )
    let prefix = "ASCII\u{0}".to_bytes()

    for byte in 128..256:
        let invalid = Bytes([byte.to_uint8().get(0)])
        try expect_equal(ascii_decode(invalid), expected)
        try expect_equal(ascii_decode(invalid.concat(prefix)), expected)
        try expect_equal(ascii_decode(prefix.concat(invalid)), expected)

test "ASCII decoding rejects valid non-ASCII UTF-8":
    let expected: String! = error(
        Error("encoding: invalid data", kind: ErrorCategory.InvalidData)
    )
    for text in ["é", "🙂", "\u{80}", "Aé", "éA", "a\u{301}"]:
        try expect_equal(ascii_decode(text.to_bytes()), expected)

test "ASCII decoding preserves large offset views and rejects high byte tails":
    let expected = try "Az09 \n\u{0}\u{7f}".repeat(4096)
    let padded = ("é" + expected + "é").to_bytes()
    let data = try padded.slice(2, 2 + expected.byte_length())
    let decode: fn(Bytes) String! = ascii_decode
    try expect_equal(try decode(data), expected)
    try expect_equal(try decode(data), data.decode_utf8().get())
    try expect_equal(data.length(), expected.byte_length())

    let invalid: String! = error(
        Error("encoding: invalid data", kind: ErrorCategory.InvalidData)
    )
    let high = Bytes([128])
    try expect_equal(decode(high.concat(data)), invalid)
    try expect_equal(decode(data.concat(high)), invalid)
    try expect_equal(decode(data.concat("é".to_bytes())), invalid)
