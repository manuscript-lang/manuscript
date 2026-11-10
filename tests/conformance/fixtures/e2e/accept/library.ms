// conform: tags=control-flow,interpolation,match,modules,stdlib-archive,stdlib-binary,stdlib-bytes,stdlib-compress,stdlib-crypto,stdlib-encoding,stdlib-json,stdlib-math,stdlib-string,stdlib-testing,stdlib-url,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/library.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import Bytes from "@std/bytes.ms"
import parse from "@std/data/json.ms"
import stringify from "@std/data/json.ms"
import JsonOptions from "@std/data/json.ms"
import StringifyOptions from "@std/data/json.ms"
import JsonValue from "@std/data/json.ms"
import hex_encode from "@std/data/encoding.ms"
import hex_decode from "@std/data/encoding.ms"
import base64_decode from "@std/data/encoding.ms"
import sha256 from "@std/crypto.ms"
import from_scalars from "@std/string.ms"
import parse_query from "@std/net/url.ms"
import format_query from "@std/net/url.ms"
import sqrt from "@std/math/math.ms"
import round from "@std/math/math.ms"
import BytesBuilder from "@std/bytes.ms"
import compress from "@std/io/archive.ms"
import decompress from "@std/io/archive.ms"
import pack from "@std/io/archive.ms"
import unpack from "@std/io/archive.ms"
import ArchiveEntry from "@std/io/archive.ms"
import ArchiveOptions from "@std/io/archive.ms"
import ArchiveFormat from "@std/io/archive.ms"
import CompressionFormat from "@std/io/archive.ms"
import CompressOptions from "@std/io/archive.ms"

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

fn verify_json() Unit!:
    limits := JsonOptions(max_bytes: 1024, max_depth: 8, max_values: 32)
    value := try parse(
        text: "\{\"large\":9007199254740993,\"ok\":true\}", options: limits
    )
    (
        not (
            try stringify(
                value: value, options: StringifyOptions(max_bytes: 1024)
            ) == "\{\"large\":9007199254740993,\"ok\":true\}"
        )
    ) | try expect_false

fn verify_encoding() Unit!:
    bytes := try hex_decode(text: "00ff42", max_bytes: 3)
    hex_encode(data: bytes) | try expect_equal("00ff42")
    (
        not (
            hex_encode(
                data: sha256(data: "abc".to_bytes())
            ) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    ) | try expect_false

fn verify_url() Unit!:
    query := try parse_query(text: "a=1&a=2&space=hello+world", max_entries: 3)
    query.length() | try expect_equal(3)
    format_query(entries: query) | try expect_equal("a=1&a=2&space=hello+world")

fn verify_binary() Unit!:
    var out = BytesBuilder()
    out.append_int16_be(-32768)
    (try out.build().int16_be(0)).to_int() | try expect_equal(-32768)

fn verify_compression() Unit!:
    compressed := try compress(
        data: "hello hello hello".to_bytes(), format: CompressionFormat.Gzip,
        options: CompressOptions(level: 6, max_bytes: 256)
    )
    (
        not (
            try decompress(
                data: compressed, format: CompressionFormat.Gzip, max_bytes: 17
            ) == "hello hello hello".to_bytes()
        )
    ) | try expect_false

fn verify_archive() Unit!:
    entries := [
        ArchiveEntry(
            path: "hello.txt", data: "hello".to_bytes(), directory: false
        )
    ]
    archive := try pack(entries: entries, format: ArchiveFormat.Zip, max_bytes: 1024)
    (
        not (
            try unpack(
                data: archive,
                format: ArchiveFormat.Zip,
                options: ArchiveOptions(
                    max_entries: 1, max_entry_bytes: 5, max_bytes: 5
                )
            ) == entries
        )
    ) | try expect_false

test "expanded packages run through compiler":
    match verify_json():
        ok(_):
            _verified := unit
        error(_):
            return fail(message: "json failed")

    match verify_encoding():
        ok(_):
            _verified := unit
        error(_):
            return fail(message: "encoding failed")

    match verify_url():
        ok(_):
            _verified := unit
        error(_):
            return fail(message: "url failed")

    match verify_binary():
        ok(_):
            _verified := unit
        error(_):
            return fail(message: "binary failed")

    match verify_compression():
        ok(_):
            _verified := unit
        error(_):
            return fail(message: "compression failed")

    match verify_archive():
        ok(_):
            _verified := unit
        error(_):
            return fail(message: "archive failed")

    ("a,,b").split(separator: ",", max_parts: 2) | try expect_equal(["a", ""])
    ("é🙂").scalar_length() | try expect_equal(2)
    ("é").scalar_values() | try expect_equal([233])

    text_success: String! = ok("é")
    from_scalars(values: [233]) | try expect_equal(text_success)
    sqrt(value: 9.0) | try expect_equal(3.0)
    round(value: 2.5) | try expect_equal(3.0)
    ([1, 2]).map(transform: twice) | try expect_equal([2, 4])
    ([-1, 3, 0, 2]).filter(predicate: positive) | try expect_equal([3, 2])
    ([1, 2, 3]).fold(initial: 0, step: sum) | try expect_equal(6)
    ([3, 1, 2]).sorted(compare: compare) | try expect_equal([1, 2, 3])

    var flipped = [1, 2]
    flipped.reverse()
    flipped | try expect_equal([2, 1])

test "malformed and bounded inputs return errors":
    failure1: Bytes! = error(Error("encoding: invalid data", kind: "EBADMSG"))
    base64_decode(text: "Zh==", url_safe: false, max_bytes: 10) | try expect_equal(
        failure1
    )

    failure2: Bytes! = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
    hex_decode(text: "abcd", max_bytes: 1) | try expect_equal(failure2)

    limits := JsonOptions(max_bytes: 100, max_depth: 2, max_values: 10)
    failure3 := parse(text: "\{\"a\":1,\"a\":2\}", options: limits)
    (
        failure3.err().message | try expect_equal(
            "JSON: invalid data: line 1, column 14: duplicate object key"
        )
    )

    failure4: JsonValue! = error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
    parse(text: "[[[]]]", options: limits) | try expect_equal(failure4)
