import {expect_equal, expect_ok} from "@std/testing.ms"
import {compress, decompress, CompressionFormat, CompressionError} from "@std/compress.ms"
import Bytes from "@std/bytes.ms"

fn forwarded[T](item: T) -> T: item

fn supplied(log: List[String], data: Bytes) -> Bytes:
    log.append("data")
    return data

fn chosen(log: List[String], format: String) -> String:
    log.append("format")
    return format

test "compression omission equals explicit level six for every format":
    let data = "repeat repeat repeat repeat".to_bytes()
    let formats = [
        CompressionFormat.Gzip,
        CompressionFormat.Zlib,
        CompressionFormat.Deflate
    ]
    let names = ["gzip", "zlib", "deflate"]
    let encode = compress
    let alias = encode
    var index = 0

    for format in formats:
        let name = names.at(index).unwrap()
        index = index + 1
        let expected = (compress(data, name, 6) | try expect_ok)
        alias(data, name) | try expect_ok | try expect_equal(expected: expected)
        compress(data, name, max_bytes: none) | try expect_ok | try expect_equal(
            expected: expected
        )
        let method = format.compress
        let copied = method
        copied(data) | try expect_ok | try expect_equal(expected: expected)
        method(data, level: 6) | try expect_ok | try expect_equal(expected: expected)
        format.compress(data, max_bytes: expected.length()) | try expect_ok | try expect_equal(
            expected: expected
        )
        format.decompress(expected) | try expect_ok | try expect_equal(expected: data)
        decompress(expected, name) | try expect_ok | try expect_equal(expected: data)

        for level in [0, 9]:
            let output = (format.compress(data, level) | try expect_ok)
            decompress(output, name) | try expect_ok | try expect_equal(expected: data)

        let full = forwarded(method)
        let free = forwarded(compress)
        free(data, name, 6, none) | try expect_ok | try expect_equal(expected: expected)
        full(data, 6, none) | try expect_ok | try expect_equal(expected: expected)

test "compression defaults retain invalid levels formats and output budgets":
    let data = "abc".to_bytes()
    let invalid: Result[Bytes, CompressionError] = error(CompressionError.InvalidInput)
    let limited: Result[Bytes, CompressionError] = error(CompressionError.LimitExceeded)
    let unsupported: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )

    for format in [
        CompressionFormat.Gzip,
        CompressionFormat.Zlib,
        CompressionFormat.Deflate
    ]:
        format.compress(data, -1) | try expect_equal(expected: invalid)
        format.compress(data, 10) | try expect_equal(expected: invalid)
        format.compress(data, max_bytes: -1) | try expect_equal(expected: invalid)
        format.compress(data, max_bytes: 0) | try expect_equal(expected: limited)
        let method = format.compress
        method(data, max_bytes: 1) | try expect_equal(expected: limited)

    compress(data, "invalid") | try expect_equal(expected: unsupported)
    compress(data, "gzip", -1) | try expect_equal(expected: invalid)
    compress(data, "gzip", max_bytes: -1) | try expect_equal(expected: invalid)
    compress(data, "gzip", max_bytes: 0) | try expect_equal(expected: limited)

test "compression default preparation retains supplied argument order":
    let log: List[String] = []
    let data = "data".to_bytes()
    let encoded = (
        compress(
            format: chosen(log, "gzip"),
            data: supplied(log, data)
        ) | try expect_ok
    )
    log | try expect_equal(expected: ["format", "data"])
    decompress(encoded, "gzip") | try expect_ok | try expect_equal(expected: data)
