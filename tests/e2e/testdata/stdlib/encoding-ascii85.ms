import Bytes, BytesBuilder from "@std/bytes.ms"
import ascii85_encode, ascii85_decode, EncodingError from "@std/data/encoding.ms"
import expect_equal from "@std/test/test.ms"

test "ASCII85 unframed vectors cover tails zero shorthand and maximum words":
    for text in ["", "f", "fo", "foo", "foob", "fooba", "foobar", "hello", "Man sure."]:
        try expect_equal(
            try ascii85_decode(ascii85_encode(text.to_bytes())), text.to_bytes()
        )
    try expect_equal(ascii85_encode("hello".to_bytes()), "BOu!rDZ")
    try expect_equal(ascii85_encode("Man sure.".to_bytes()), "9jqo^F*2M7/c")
    try expect_equal(ascii85_encode(Bytes([0])), "!!")
    try expect_equal(ascii85_encode(Bytes([0, 0])), "!!!")
    try expect_equal(ascii85_encode(Bytes([0, 0, 0])), "!!!!")
    try expect_equal(ascii85_encode(Bytes([0, 0, 0, 0])), "z")
    try expect_equal(ascii85_encode(Bytes([0, 0, 0, 0, 0])), "z!!")
    try expect_equal(ascii85_encode(Bytes([0, 0, 0, 1])), "!!!!\"")
    try expect_equal(ascii85_encode(Bytes([255, 255, 255, 255])), "s8W-!")
    try expect_equal(try ascii85_decode("s8W-!"), Bytes([255, 255, 255, 255]))
    try expect_equal(try ascii85_decode("rr"), Bytes([255]))
    try expect_equal(try ascii85_decode("s8N"), Bytes([255, 255]))
    try expect_equal(try ascii85_decode("s8W*"), Bytes([255, 255, 255]))

test "ASCII85 ignores every ASCII control and space including after complete groups":
    var out = BytesBuilder()
    for byte in 0..33: out.append(byte.to_uint8().get(0))

    let spaces = out.build().decode_utf8().get("")
    try expect_equal(try ascii85_decode(spaces, 0), Bytes([]))
    try expect_equal(try ascii85_decode("z" + spaces), Bytes([0, 0, 0, 0]))
    try expect_equal(
        try ascii85_decode(spaces + "s8W-!" + spaces), Bytes([255, 255, 255, 255])
    )
    try expect_equal(try ascii85_decode("!" + spaces + "!"), Bytes([0]))

test "ASCII85 rejects invalid characters delimiters and misplaced shorthand":
    let invalid: Bytes!EncodingError = error(EncodingError.InvalidData)
    for text in [
        "!", "u", "y", "v", "~", "!!z", "!z!!!", "<~z~>", "z~>", "z~", "é", "zé", "z!"
    ]:
        try expect_equal(ascii85_decode(text), invalid)

    let non_ascii = Bytes([127]).decode_utf8().get("")
    try expect_equal(ascii85_decode(non_ascii), invalid)

test "ASCII85 rejects overflowing complete and padded partial groups":
    let invalid: Bytes!EncodingError = error(EncodingError.InvalidData)
    for text in ["s8W-\"", "s8W", "s8W-", "uu", "uuu", "uuuu", "uuuuu", "s8W-!uuuuu"]:
        try expect_equal(ascii85_decode(text), invalid)

test "ASCII85 decoded byte limits count expansions and partial groups exactly":
    let limited: Bytes!EncodingError = error(EncodingError.LimitExceeded)
    let invalid: Bytes!EncodingError = error(EncodingError.InvalidInput)
    try expect_equal(try ascii85_decode("", 0), Bytes([]))
    try expect_equal(ascii85_decode("z", 3), limited)
    try expect_equal(try ascii85_decode("z", 4), Bytes([0, 0, 0, 0]))
    try expect_equal(ascii85_decode("!!", 0), limited)
    try expect_equal(try ascii85_decode("!!", 1), Bytes([0]))
    try expect_equal(ascii85_decode("zz", 7), limited)
    try expect_equal(try ascii85_decode("zz", 8), Bytes([0, 0, 0, 0, 0, 0, 0, 0]))
    for text in ["", "?", "uuuuu"]:
        try expect_equal(ascii85_decode(text, -1), invalid)
    try expect_equal(try ascii85_decode("!!", none), Bytes([0]))

test "ASCII85 round trips byte views across every block boundary":
    var out = BytesBuilder()
    for value in 0..256: out.append(value.to_uint8().get(0))

    let bytes = out.build()

    for end in 0..256:
        let view = try bytes.slice(0, end)
        try expect_equal(try ascii85_decode(ascii85_encode(view), end), view)

    let middle = try bytes.slice(17, 219)
    try expect_equal(try ascii85_decode(ascii85_encode(middle)), middle)
