from "@std/testing.ms" import expect_equal, expect_false, fail
from "@std/bytes.ms" import Bytes
from "@std/json.ms" import parse
from "@std/json.ms" import stringify
from "@std/json.ms" import JsonLimits
from "@std/json.ms" import JsonValue
from "@std/encoding.ms" import hex_encode
from "@std/encoding.ms" import hex_decode
from "@std/encoding.ms" import base64_decode
from "@std/crypto.ms" import sha256
from "@std/string.ms" import from_scalars
from "@std/net.ms" import parse_query
from "@std/net.ms" import format_query
from "@std/math.ms" import sqrt
from "@std/math.ms" import round
from "@std/bytes.ms" import read_integer
from "@std/bytes.ms" import write_integer
from "@std/archive.ms" import compress
from "@std/archive.ms" import decompress
from "@std/json.ms" import JsonError
from "@std/encoding.ms" import EncodingError
from "@std/string.ms" import StringError
from "@std/net.ms" import UrlError
from "@std/bytes.ms" import BinaryError
from "@std/archive.ms" import CompressionError
from "@std/archive.ms" import ArchiveError
from "@std/archive.ms" import pack
from "@std/archive.ms" import unpack
from "@std/archive.ms" import ArchiveEntry
from "@std/archive.ms" import ArchiveLimits

def twice(value: Int) -> Int:
    return value * 2

def positive(value: Int) -> Bool:
    return value > 0

def sum(accumulator: Int, value: Int) -> Int:
    return accumulator + value

def compare(left: Int, right: Int) -> Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

def verify_json() -> Result[Unit, Error]:
    let limits = JsonLimits(max_bytes: 1024, max_depth: 8, max_values: 32)
    let value = try parse(
        text: "{\"large\":9007199254740993,\"ok\":true}", limits: limits
    )
    (
        not (
            try stringify(
                value: value, max_bytes: 1024
            ) == "{\"large\":9007199254740993,\"ok\":true}"
        )
    ) | try expect_false
    return ok(())

def verify_encoding() -> Result[Unit, Error]:
    let bytes = try hex_decode(text: "00ff42", max_bytes: 3)
    hex_encode(data: bytes) | try expect_equal("00ff42")
    (
        not (
            hex_encode(
                data: sha256(data: "abc".to_bytes())
            ) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    ) | try expect_false
    return ok(())

def verify_url() -> Result[Unit, Error]:
    let query = try parse_query(text: "a=1&a=2&space=hello+world", max_entries: 3)
    query.length() | try expect_equal(3)
    format_query(entries: query) | try expect_equal("a=1&a=2&space=hello+world")
    return ok(())

def verify_binary() -> Result[Unit, Error]:
    let binary = try write_integer(
        value: -32768, width: 2, signed: True, little_endian: False
    )
    (
        not (
            try read_integer(
                data: binary, offset: 0, width: 2, signed: True, little_endian: False
            ) == -32768
        )
    ) | try expect_false
    return ok(())

def verify_compression() -> Result[Unit, Error]:
    let compressed = try compress(
        data: "hello hello hello".to_bytes(), format: "gzip", level: 6, max_bytes: 256
    )
    (
        not (
            try decompress(
                data: compressed, format: "gzip", max_bytes: 17
            ) == "hello hello hello".to_bytes()
        )
    ) | try expect_false
    return ok(())

def verify_archive() -> Result[Unit, Error]:
    let entries = [
        ArchiveEntry(
            path: "hello.txt", data: "hello".to_bytes(), directory: False
        )
    ]
    let archive = try pack(entries: entries, format: "zip", max_bytes: 1024)
    (
        not (
            try unpack(
                data: archive,
                format: "zip",
                limits: ArchiveLimits(
                    max_entries: 1, max_entry_bytes: 5, max_total_bytes: 5
                )
            ) == entries
        )
    ) | try expect_false
    return ok(())

test "expanded packages run through compiler":
    match verify_json():
        case ok(_):
            let verified = ()
        case error(_):
            return fail(message: "json failed")

    match verify_encoding():
        case ok(_):
            let verified = ()
        case error(_):
            return fail(message: "encoding failed")

    match verify_url():
        case ok(_):
            let verified = ()
        case error(_):
            return fail(message: "url failed")

    match verify_binary():
        case ok(_):
            let verified = ()
        case error(_):
            return fail(message: "binary failed")

    match verify_compression():
        case ok(_):
            let verified = ()
        case error(_):
            return fail(message: "compression failed")

    match verify_archive():
        case ok(_):
            let verified = ()
        case error(_):
            return fail(message: "archive failed")

    ("a,,b").split(separator: ",", max_parts: 2) | try expect_equal(["a", ""])
    ("é🙂").scalar_length() | try expect_equal(2)
    ("é").scalar_values() | try expect_equal([233])

    let text_success: Result[String, StringError] = ok("é")
    from_scalars(values: [233]) | try expect_equal(text_success)
    sqrt(value: 9.0) | try expect_equal(3.0)
    round(value: 2.5) | try expect_equal(3.0)
    ([1, 2]).map(transform: twice) | try expect_equal([2, 4])
    ([-1, 3, 0, 2]).filter(predicate: positive) | try expect_equal([3, 2])
    ([1, 2, 3]).fold(initial: 0, step: sum) | try expect_equal(6)
    ([3, 1, 2]).sorted(compare: compare) | try expect_equal([1, 2, 3])

    var flipped = [1, 2]
    flipped.reverse_in_place()
    flipped | try expect_equal([2, 1])

test "malformed and bounded inputs return errors":
    let failure1: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    base64_decode(text: "Zh==", url_safe: False, max_bytes: 10) | try expect_equal(
        failure1
    )

    let failure2: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    hex_decode(text: "abcd", max_bytes: 1) | try expect_equal(failure2)

    let limits = JsonLimits(max_bytes: 100, max_depth: 2, max_values: 10)
    let failure3: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    parse(text: "{\"a\":1,\"a\":2}", limits: limits) | try expect_equal(failure3)

    let failure4: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    parse(text: "[[[]]]", limits: limits) | try expect_equal(failure4)

    let failure5: Result[Bytes, BinaryError] = error(BinaryError.OutOfRange)
    (
        not (
            write_integer(
                value: 256, width: 1, signed: False, little_endian: True
            ) == failure5
        )
    ) | try expect_false
