import ascii_decode, EncodingError from "@std/encoding.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import from_scalars from "@std/string.ms"
import expect_equal from "@std/test.ms"

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
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    let prefix = "ASCII\u{0}".to_bytes()

    for byte in 128..256:
        let invalid = Bytes([byte.to_uint8().get(0)])
        try expect_equal(ascii_decode(invalid), expected)
        try expect_equal(ascii_decode(invalid.concat(prefix)), expected)
        try expect_equal(ascii_decode(prefix.concat(invalid)), expected)

test "ASCII decoding rejects valid non-ASCII UTF-8":
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    for text in ["é", "🙂", "\u{80}", "Aé", "éA", "a\u{301}"]:
        try expect_equal(ascii_decode(text.to_bytes()), expected)
