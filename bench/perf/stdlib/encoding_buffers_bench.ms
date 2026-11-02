import (
    base64_encode,
    base64_encode_unpadded,
    base32_encode,
    base32_decode,
    ascii85_encode,
    ascii85_decode,
    EncodingError
) from "@std/data/encoding.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import keep, measure from "@std/test/bench.ms"
import expect_equal from "@std/test/test.ms"

fn sample(length: Int, zero: Bool = false) Bytes:
    var out = BytesBuilder()

    for index in 0..length:
        let value = if zero: 0 else: (index * 73 + 11) % 256
        out.append(value.to_uint8().get())

    return out.build()

fn unpadded(length: Int, url: Bool) Unit!:
    let data = sample(length)
    let expected = base64_encode(data, url).replace("=", "")

    fn work() Unit!:
        let actual = base64_encode_unpadded(data, url)
        try expect_equal(actual, expected)
        return keep(actual.byte_length())

    try measure(1, work)
    return ok(unit)

fn base32(length: Int, hex: Bool, padded: Bool) Unit!:
    let data = sample(length)
    let expected = base32_encode(data, hex, padded)
    try expect_equal(try base32_decode(expected, hex, padded), data)

    fn work() Unit!:
        let actual = base32_encode(data, hex, padded)
        try expect_equal(actual, expected)
        return keep(actual.byte_length())

    try measure(1, work)
    return ok(unit)

fn encode85(length: Int) Unit!:
    let data = sample(length)
    let expected = ascii85_encode(data)
    try expect_equal(try ascii85_decode(expected), data)

    fn work() Unit!:
        let actual = ascii85_encode(data)
        try expect_equal(actual, expected)
        return keep(actual.byte_length())

    try measure(1, work)
    return ok(unit)

fn decode85(
    length: Int,
    bounded: Bool,
    under: Bool,
    zero: Bool = false,
    bad: Int = 0
) Unit!:
    let data = sample(length, zero)
    var text = ascii85_encode(data)
    if bad == 1: text = "v" + text
    if bad == 2: text = text + "v"

    var limit: Int? = none
    if bounded: limit = if under: length - 1 else: length

    var expected: Bytes!EncodingError = ok(data.clone())
    if under: expected = error(EncodingError.LimitExceeded)
    if bad != 0: expected = error(EncodingError.InvalidData)

    fn work() Unit!:
        let actual = ascii85_decode(text, limit)
        try expect_equal(actual, expected)
        return keep(if actual.is_ok(): data.length() else: 1)

    try measure(1, work)
    return ok(unit)

fn zero_budget85() Unit!:
    let text = ascii85_encode(sample(4096))
    let expected: Bytes!EncodingError = error(EncodingError.LimitExceeded)

    fn work() Unit!:
        try expect_equal(ascii85_decode(text, 0), expected)
        return keep(1)

    try measure(1, work)
    return ok(unit)

fn whitespace85(bounded: Bool) Unit!:
    let text = try " \t\r\n".repeat(16384)
    let limit: Int? = if bounded: 0 else: none
    let expected: Bytes!EncodingError = ok(Bytes([]))

    fn work() Unit!:
        try expect_equal(ascii85_decode(text, limit), expected)
        return keep(1)

    try measure(1, work)
    return ok(unit)

bench "buffers.unpadded.std.0":
    try unpadded(0, false)

bench "buffers.unpadded.std.4":
    try unpadded(4, false)

bench "buffers.unpadded.std.7":
    try unpadded(7, false)

bench "buffers.unpadded.std.21":
    try unpadded(21, false)

bench "buffers.unpadded.std.4096":
    try unpadded(4096, false)

bench "buffers.unpadded.std.1048576":
    try unpadded(1048576, false)

bench "buffers.unpadded.url.21":
    try unpadded(21, true)

bench "buffers.unpadded.url.4096":
    try unpadded(4096, true)

bench "buffers.base32.std.pad.21":
    try base32(21, false, true)

bench "buffers.base32.std.raw.4096":
    try base32(4096, false, false)

bench "buffers.base32.hex.pad.4096":
    try base32(4096, true, true)

bench "buffers.base32.hex.raw.21":
    try base32(21, true, false)

bench "buffers.ascii85.encode.21":
    try encode85(21)

bench "buffers.ascii85.encode.4096":
    try encode85(4096)

bench "buffers.ascii85.none.0":
    try decode85(0, false, false)

bench "buffers.ascii85.exact.0":
    try decode85(0, true, false)

bench "buffers.ascii85.none.8":
    try decode85(8, false, false)

bench "buffers.ascii85.exact.8":
    try decode85(8, true, false)

bench "buffers.ascii85.none.4096":
    try decode85(4096, false, false)

bench "buffers.ascii85.exact.4096":
    try decode85(4096, true, false)

bench "buffers.ascii85.under.8":
    try decode85(8, true, true)

bench "buffers.ascii85.under.4096":
    try decode85(4096, true, true)

bench "buffers.ascii85.zero.4096":
    try zero_budget85()

bench "buffers.ascii85.invalid.first":
    try decode85(4096, true, false, bad: 1)

bench "buffers.ascii85.invalid.last":
    try decode85(4096, true, false, bad: 2)

bench "buffers.ascii85.z.none":
    try decode85(8, false, false, true)

bench "buffers.ascii85.z.exact":
    try decode85(8, true, false, true)

bench "buffers.ascii85.z.under":
    try decode85(8, true, true, true)

bench "buffers.ascii85.whitespace.none":
    try whitespace85(false)

bench "buffers.ascii85.whitespace.exact":
    try whitespace85(true)
