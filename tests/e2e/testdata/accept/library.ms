import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import parse from "@std/json.ms"
import stringify from "@std/json.ms"
import JsonLimits from "@std/json.ms"
import JsonValue from "@std/json.ms"
import hex_encode from "@std/encoding.ms"
import hex_decode from "@std/encoding.ms"
import base64_decode from "@std/encoding.ms"
import sha256 from "@std/crypto.ms"
import split from "@std/text.ms"
import scalar_values from "@std/text.ms"
import from_scalars from "@std/text.ms"
import scalar_length from "@std/text.ms"
import parse_query from "@std/url.ms"
import format_query from "@std/url.ms"
import sqrt from "@std/math.ms"
import round from "@std/math.ms"
import multiply from "@std/bigint.ms"
import read_integer from "@std/binary.ms"
import write_integer from "@std/binary.ms"
import compress from "@std/compress.ms"
import decompress from "@std/compress.ms"
import LibraryError from "@std/errors.ms"
import Result from "@std/result.ms"
import map from "@std/collections.ms"
import filter from "@std/collections.ms"
import fold from "@std/collections.ms"
import sorted from "@std/collections.ms"
import reverse from "@std/collections.ms"
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

fn verify_formats() -> Result[Unit, LibraryError]:
    let limits = JsonLimits(max_bytes: 1024, max_depth: 8, max_values: 32)
    let value = try parse(text: "\{\"large\":9007199254740993,\"ok\":true\}", limits: limits)
    assert try stringify(value: value, max_bytes: 1024) == "\{\"large\":9007199254740993,\"ok\":true\}"
    let bytes = try hex_decode(text: "00ff42", max_bytes: 3)
    assert hex_encode(data: bytes) == "00ff42"
    assert hex_encode(data: sha256(data: "abc".to_bytes())) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    let query = try parse_query(text: "a=1&a=2&space=hello+world", max_entries: 3)
    assert query.length() == 3
    assert format_query(entries: query) == "a=1&a=2&space=hello+world"
    let binary = try write_integer(value: -32768, width: 2, signed: true, little_endian: false)
    assert try read_integer(data: binary, offset: 0, width: 2, signed: true, little_endian: false) == -32768
    let compressed = try compress(data: "hello hello hello".to_bytes(), format: "gzip", level: 6, max_bytes: 256)
    assert try decompress(data: compressed, format: "gzip", max_bytes: 17) == "hello hello hello".to_bytes()
    let entries = [ArchiveEntry(path: "hello.txt", data: "hello".to_bytes(), directory: false)]
    let archive = try pack(entries: entries, format: "zip", max_bytes: 1024)
    assert try unpack(data: archive, format: "zip", limits: ArchiveLimits(max_entries: 1, max_entry_bytes: 5, max_total_bytes: 5)) == entries
    return ok(value: unit)

test "expanded packages run through compiler":
    let success: Result[Unit, LibraryError] = ok(value: unit)
    assert verify_formats() == success
    assert split(text: "a,,b", separator: ",", max_parts: 2) == ["a", ",b"]
    assert scalar_length(text: "é🙂") == 2
    assert scalar_values(text: "é") == [233]
    let text_success: Result[String, LibraryError] = ok(value: "é")
    assert from_scalars(values: [233]) == text_success
    assert sqrt(value: 9.0) == 3.0
    assert round(value: 2.5) == 2.0
    assert map(values: [1, 2], transform: twice) == [2, 4]
    assert filter(values: [-1, 3, 0, 2], predicate: positive) == [3, 2]
    assert fold(values: [1, 2, 3], initial: 0, step: sum) == 6
    assert sorted(values: [3, 1, 2], compare: compare) == [1, 2, 3]
    let reverse_int = reverse[Int]
    assert reverse_int(values: [1, 2]) == [2, 1]

test "malformed and bounded inputs return errors":
    let failure1: Result[Bytes, LibraryError] = error(cause: InvalidData)
    assert base64_decode(text: "Zh==", url_safe: false, max_bytes: 10) == failure1
    let failure2: Result[Bytes, LibraryError] = error(cause: LimitExceeded)
    assert hex_decode(text: "abcd", max_bytes: 1) == failure2
    let limits = JsonLimits(max_bytes: 100, max_depth: 2, max_values: 10)
    let failure3: Result[JsonValue, LibraryError] = error(cause: InvalidData)
    assert parse(text: "\{\"a\":1,\"a\":2\}", limits: limits) == failure3
    let failure4: Result[JsonValue, LibraryError] = error(cause: LimitExceeded)
    assert parse(text: "[[[]]]", limits: limits) == failure4
    let failure5: Result[Bytes, LibraryError] = error(cause: OutOfRange)
    assert write_integer(value: 256, width: 1, signed: false, little_endian: true) == failure5
