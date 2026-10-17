import panic from "@std/faults.ms"
import Bytes from "@std/bytes.ms"
import parse from "@std/json.ms"
import stringify from "@std/json.ms"
import JsonLimits from "@std/json.ms"
import JsonValue from "@std/json.ms"
import hex_encode from "@std/encoding.ms"
import hex_decode from "@std/encoding.ms"
import base64_decode from "@std/encoding.ms"
import sha256 from "@std/crypto.ms"
import from_scalars from "@std/string.ms"
import parse_query from "@std/url.ms"
import format_query from "@std/url.ms"
import sqrt from "@std/math.ms"
import round from "@std/math.ms"
import read_integer from "@std/binary.ms"
import write_integer from "@std/binary.ms"
import compress from "@std/compress.ms"
import decompress from "@std/compress.ms"
import JsonError from "@std/json.ms"
import EncodingError from "@std/encoding.ms"
import StringError from "@std/string.ms"
import UrlError from "@std/url.ms"
import BinaryError from "@std/binary.ms"
import CompressionError from "@std/compress.ms"
import ArchiveError from "@std/archive.ms"
import pack from "@std/archive.ms"
import unpack from "@std/archive.ms"
import ArchiveEntry from "@std/archive.ms"
import ArchiveLimits from "@std/archive.ms"

fn twice(value: Int) -> Int:
    return value * 2

fn positive(value: Int) -> Bool:
    return value > 0

fn sum(accumulator: Int, value: Int) -> Int:
    return accumulator + value

fn compare(left: Int, right: Int) -> Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

fn verify_json() -> Result[Unit, JsonError]:
    let limits = JsonLimits(max_bytes: 1024, max_depth: 8, max_values: 32)
    let value = try parse(
        text: "\{\"large\":9007199254740993,\"ok\":true\}",
        limits: limits
    )
    if not (
        try stringify(
            value: value,
            max_bytes: 1024
        ) == "\{\"large\":9007199254740993,\"ok\":true\}"
    ):
        return panic(message: "check failed")

    return ok(unit)

fn verify_encoding() -> Result[Unit, EncodingError]:
    let bytes = try hex_decode(text: "00ff42", max_bytes: 3)
    if not (hex_encode(data: bytes) == "00ff42"):
        return panic(message: "check failed")
    if not (
        hex_encode(
            data: sha256(data: "abc".to_bytes())
        ) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    ):
        return panic(message: "check failed")

    return ok(unit)

fn verify_url() -> Result[Unit, UrlError]:
    let query = try parse_query(text: "a=1&a=2&space=hello+world", max_entries: 3)
    if not (query.length() == 3):
        return panic(message: "check failed")
    if not (format_query(entries: query) == "a=1&a=2&space=hello+world"):
        return panic(message: "check failed")

    return ok(unit)

fn verify_binary() -> Result[Unit, BinaryError]:
    let binary = try write_integer(
        value: -32768,
        width: 2,
        signed: true,
        little_endian: false
    )
    if not (
        try read_integer(
            data: binary,
            offset: 0,
            width: 2,
            signed: true,
            little_endian: false
        ) == -32768
    ):
        return panic(message: "check failed")

    return ok(unit)

fn verify_compression() -> Result[Unit, CompressionError]:
    let compressed = try compress(
        data: "hello hello hello".to_bytes(),
        format: "gzip",
        level: 6,
        max_bytes: 256
    )
    if not (
        try decompress(
            data: compressed,
            format: "gzip",
            max_bytes: 17
        ) == "hello hello hello".to_bytes()
    ):
        return panic(message: "check failed")

    return ok(unit)

fn verify_archive() -> Result[Unit, ArchiveError]:
    let entries = [
        ArchiveEntry(
            path: "hello.txt",
            data: "hello".to_bytes(),
            directory: false
        )
    ]
    let archive = try pack(entries: entries, format: "zip", max_bytes: 1024)
    if not (
        try unpack(
            data: archive,
            format: "zip",
            limits: ArchiveLimits(
                max_entries: 1,
                max_entry_bytes: 5,
                max_total_bytes: 5
            )
        ) == entries
    ):
        return panic(message: "check failed")

    return ok(unit)

test "expanded packages run through compiler":
    try verify_json()
    try verify_encoding()
    try verify_url()
    try verify_binary()
    try verify_compression()
    try verify_archive()
    if not (("a,,b").split(separator: ",", max_parts: 2) == ["a", ""]):
        return panic(message: "check failed")
    if not (("é🙂").scalar_length() == 2):
        return panic(message: "check failed")
    if not (("é").scalar_values() == [233]):
        return panic(message: "check failed")

    let text_success: Result[String, StringError] = ok("é")
    if not (from_scalars(values: [233]) == text_success):
        return panic(message: "check failed")
    if not (sqrt(value: 9.0) == 3.0):
        return panic(message: "check failed")
    if not (round(value: 2.5) == 3.0):
        return panic(message: "check failed")
    if not (([1, 2]).map(transform: twice) == [2, 4]):
        return panic(message: "check failed")
    if not (([-1, 3, 0, 2]).filter(predicate: positive) == [3, 2]):
        return panic(message: "check failed")
    if not (([1, 2, 3]).fold(initial: 0, step: sum) == 6):
        return panic(message: "check failed")
    if not (([3, 1, 2]).sorted(compare: compare) == [1, 2, 3]):
        return panic(message: "check failed")

    let reverse_int = [1, 2].reverse_in_place
    if not (reverse_int() == [2, 1]):
        return panic(message: "check failed")

test "malformed and bounded inputs return errors":
    let failure1: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    if not (base64_decode(text: "Zh==", url_safe: false, max_bytes: 10) == failure1):
        return panic(message: "check failed")

    let failure2: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    if not (hex_decode(text: "abcd", max_bytes: 1) == failure2):
        return panic(message: "check failed")

    let limits = JsonLimits(max_bytes: 100, max_depth: 2, max_values: 10)
    let failure3: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    if not (parse(text: "\{\"a\":1,\"a\":2\}", limits: limits) == failure3):
        return panic(message: "check failed")

    let failure4: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    if not (parse(text: "[[[]]]", limits: limits) == failure4):
        return panic(message: "check failed")

    let failure5: Result[Bytes, BinaryError] = error(BinaryError.OutOfRange)
    if not (
        write_integer(
            value: 256,
            width: 1,
            signed: false,
            little_endian: true
        ) == failure5
    ):
        return panic(message: "check failed")
