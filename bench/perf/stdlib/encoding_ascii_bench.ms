import ascii_decode, EncodingError from "@std/data/encoding.ms"
import Bytes from "@std/bytes.ms"
import keep, measure from "@std/test/bench.ms"
import expect_equal from "@std/test/test.ms"

bench "ascii.valid.0":
    let expected = try "Az09 \n\u{0}".repeat(0)
    let data = expected.to_bytes()
    try expect_equal(data.length(), 0)
    try expect_equal(try ascii_decode(data), expected)
    try measure(1, fn: keep((try ascii_decode(data)).byte_length()))

bench "ascii.valid.7":
    let expected = try "Az09 \n\u{0}".repeat(1)
    let data = expected.to_bytes()
    try expect_equal(data.length(), 7)
    try expect_equal(try ascii_decode(data), expected)
    try measure(1, fn: keep((try ascii_decode(data)).byte_length()))

bench "ascii.valid.56":
    let expected = try "Az09 \n\u{0}".repeat(8)
    let data = expected.to_bytes()
    try expect_equal(data.length(), 56)
    try expect_equal(try ascii_decode(data), expected)
    try measure(1, fn: keep((try ascii_decode(data)).byte_length()))

bench "ascii.valid.4095":
    let expected = try "Az09 \n\u{0}".repeat(585)
    let data = expected.to_bytes()
    try expect_equal(data.length(), 4095)
    try expect_equal(try ascii_decode(data), expected)
    try measure(1, fn: keep((try ascii_decode(data)).byte_length()))

bench "ascii.valid.1048579":
    let expected = try "Az09 \n\u{0}".repeat(149797)
    let data = expected.to_bytes()
    try expect_equal(data.length(), 1048579)
    try expect_equal(try ascii_decode(data), expected)
    try measure(1, fn: keep((try ascii_decode(data)).byte_length()))

bench "ascii.invalid.first.1":
    let good = (try "Az09 \n\u{0}".repeat(0)).to_bytes()
    let bad = Bytes([255])
    let data = bad.concat(good)
    try expect_equal(data.length(), 1)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.last.1":
    let good = (try "Az09 \n\u{0}".repeat(0)).to_bytes()
    let bad = Bytes([255])
    let data = good.concat(bad)
    try expect_equal(data.length(), 1)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.first.57":
    let good = (try "Az09 \n\u{0}".repeat(8)).to_bytes()
    let bad = Bytes([255])
    let data = bad.concat(good)
    try expect_equal(data.length(), 57)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.last.57":
    let good = (try "Az09 \n\u{0}".repeat(8)).to_bytes()
    let bad = Bytes([255])
    let data = good.concat(bad)
    try expect_equal(data.length(), 57)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.first.4096":
    let good = (try "Az09 \n\u{0}".repeat(585)).to_bytes()
    let bad = Bytes([255])
    let data = bad.concat(good)
    try expect_equal(data.length(), 4096)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.last.4096":
    let good = (try "Az09 \n\u{0}".repeat(585)).to_bytes()
    let bad = Bytes([255])
    let data = good.concat(bad)
    try expect_equal(data.length(), 4096)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.first.1048580":
    let good = (try "Az09 \n\u{0}".repeat(149797)).to_bytes()
    let bad = Bytes([255])
    let data = bad.concat(good)
    try expect_equal(data.length(), 1048580)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.invalid.last.1048580":
    let good = (try "Az09 \n\u{0}".repeat(149797)).to_bytes()
    let bad = Bytes([255])
    let data = good.concat(bad)
    try expect_equal(data.length(), 1048580)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        let actual = ascii_decode(data)
        try expect_equal(actual, expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.accent.1":
    let data = (try "é".repeat(1)).to_bytes()
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.emoji.1":
    let data = (try "🙂".repeat(1)).to_bytes()
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.accent.2048":
    let data = (try "é".repeat(2048)).to_bytes()
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.emoji.2048":
    let data = (try "🙂".repeat(2048)).to_bytes()
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.accent.524288":
    let data = (try "é".repeat(524288)).to_bytes()
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.emoji.524288":
    let data = (try "🙂".repeat(524288)).to_bytes()
    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.first.8":
    let tail = try "A".repeat(8)
    let data = ("é" + tail).to_bytes()
    try expect_equal(data.length(), 10)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.last.8":
    let tail = try "A".repeat(8)
    let data = (tail + "é").to_bytes()
    try expect_equal(data.length(), 10)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.first.524288":
    let tail = try "A".repeat(524288)
    let data = ("é" + tail).to_bytes()
    try expect_equal(data.length(), 524290)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)

bench "ascii.unicode.last.524288":
    let tail = try "A".repeat(524288)
    let data = (tail + "é").to_bytes()
    try expect_equal(data.length(), 524290)

    let expected: String!EncodingError = error(EncodingError.InvalidData)
    try expect_equal(ascii_decode(data), expected)

    fn work() Unit!:
        try expect_equal(ascii_decode(data), expected)
        return keep(data.length())

    try measure(1, work)
