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

fn twice(value: Int) Int:
    return value * 2

fn positive(value: Int) Bool:
    return value > 0

fn sum(accumulator: Int, value: Int) Int:
    return accumulator + value

fn compare(left: Int, right: Int) Int:
    if left < right:
        return -1
    if left > right:
        return 1

    return 0

fn verify_json() Result[Unit, JsonError]:
    let limits = JsonLimits(1024, 8, 32)
    let value = try parse("\{\"large\":9007199254740993,\"ok\":true\}", limits)
    if not (try stringify(value, 1024) == "\{\"large\":9007199254740993,\"ok\":true\}"):
        return panic("check failed")

    return ok(unit)

fn verify_encoding() Result[Unit, EncodingError]:
    let bytes = try hex_decode("00ff42", 3)
    if not (hex_encode(bytes) == "00ff42"):
        return panic("check failed")
    if not (
        hex_encode(
            sha256("abc".to_bytes())
        ) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    ):
        return panic("check failed")

    return ok(unit)

fn verify_url() Result[Unit, UrlError]:
    let query = try parse_query("a=1&a=2&space=hello+world", 3)
    if not (query.length() == 3):
        return panic("check failed")
    if not (format_query(query) == "a=1&a=2&space=hello+world"):
        return panic("check failed")

    return ok(unit)

fn verify_binary() Result[Unit, BinaryError]:
    let binary = try write_integer(-32768, 2, signed: true, little_endian: false)
    if not (
        try read_integer(
            binary,
            0,
            2,
            signed: true,
            little_endian: false
        ) == -32768
    ):
        return panic("check failed")

    return ok(unit)

fn verify_compression() Result[Unit, CompressionError]:
    let compressed = try compress("hello hello hello".to_bytes(), "gzip", 6, 256)
    if not (try decompress(compressed, "gzip", 17) == "hello hello hello".to_bytes()):
        return panic("check failed")

    return ok(unit)

fn verify_archive() Result[Unit, ArchiveError]:
    let entries = [ArchiveEntry("hello.txt", "hello".to_bytes(), directory: false)]
    let archive = try pack(entries, "zip", 1024)
    if not (try unpack(archive, "zip", ArchiveLimits(1, 5, 5)) == entries):
        return panic("check failed")

    return ok(unit)

test "expanded packages run through compiler":
    try verify_json()
    try verify_encoding()
    try verify_url()
    try verify_binary()
    try verify_compression()
    try verify_archive()
    if not (("a,,b").split(",", 2) == ["a", ""]):
        return panic("check failed")
    if not (("é🙂").scalar_length() == 2):
        return panic("check failed")
    if not (("é").scalar_values() == [233]):
        return panic("check failed")

    let text_success: Result[String, StringError] = ok("é")
    if not (from_scalars([233]) == text_success):
        return panic("check failed")
    if not (sqrt(9.0) == 3.0):
        return panic("check failed")
    if not (round(2.5) == 3.0):
        return panic("check failed")
    if not (([1, 2]).map(twice) == [2, 4]):
        return panic("check failed")
    if not (([-1, 3, 0, 2]).filter(positive) == [3, 2]):
        return panic("check failed")
    if not (([1, 2, 3]).fold(0, sum) == 6):
        return panic("check failed")
    if not (([3, 1, 2]).sorted(compare) == [1, 2, 3]):
        return panic("check failed")

    let reverse_int = [1, 2].reverse_in_place
    if not (reverse_int() == [2, 1]):
        return panic("check failed")

test "malformed and bounded inputs return errors":
    let failure1: Result[Bytes, EncodingError] = error(EncodingError.InvalidData)
    if not (base64_decode("Zh==", url_safe: false, max_bytes: 10) == failure1):
        return panic("check failed")

    let failure2: Result[Bytes, EncodingError] = error(EncodingError.LimitExceeded)
    if not (hex_decode("abcd", 1) == failure2):
        return panic("check failed")

    let limits = JsonLimits(100, 2, 10)
    let failure3: Result[JsonValue, JsonError] = error(JsonError.InvalidData)
    if not (parse("\{\"a\":1,\"a\":2\}", limits) == failure3):
        return panic("check failed")

    let failure4: Result[JsonValue, JsonError] = error(JsonError.LimitExceeded)
    if not (parse("[[[]]]", limits) == failure4):
        return panic("check failed")

    let failure5: Result[Bytes, BinaryError] = error(BinaryError.OutOfRange)
    if not (write_integer(256, 1, signed: false, little_endian: true) == failure5):
        return panic("check failed")
