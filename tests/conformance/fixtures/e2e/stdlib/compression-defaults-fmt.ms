# conform: tags=aliasing,control-flow,faults,formatter,generics,lists,modules,mutation,parser,stdlib-bytes,stdlib-compress,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/compression-defaults.ms
import expect_equal from "@std/test.ms"
import compress, decompress, CompressionFormat, CompressionError from "@std/archive.ms"
import Bytes from "@std/bytes.ms"

fn forwarded[T](item: T) T: item

fn supplied(var log: List[String], data: Bytes) Bytes:
    log.append("data")
    return data

fn chosen(var log: List[String], format: String) String:
    log.append("format")
    return format

test "compression omission equals explicit level six for every format":
    let data = "repeat repeat repeat repeat".to_bytes()
    let formats = [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]
    let names = ["gzip", "zlib", "deflate"]
    let encode = compress
    let alias = encode
    var index = 0

    for format in formats:
        let name = names.get(index)
        index += 1

        let expected = try compress(data, name, 6)
        try expect_equal((try alias(data, name)), expected)
        try expect_equal((try compress(data, name, max_bytes: none)), expected)

        let method = format.compress
        let copied = method
        try expect_equal((try copied(data)), expected)
        try expect_equal((try method(data, 6)), expected)
        try expect_equal(
            (try format.compress(data, max_bytes: expected.length())), expected
        )
        try expect_equal((try format.decompress(expected)), data)
        try expect_equal((try decompress(expected, name)), data)

        for level in [0, 9]:
            let output = try format.compress(data, level)
            try expect_equal((try decompress(output, name)), data)

        let full = forwarded(method)
        let free = forwarded(compress)
        try expect_equal((try free(data, name, 6, none)), expected)
        try expect_equal((try full(data, 6, none)), expected)

test "compression defaults retain invalid levels formats and output budgets":
    let data = "abc".to_bytes()
    let invalid: Result[Bytes, CompressionError] = error(CompressionError.InvalidInput)
    let limited: Result[Bytes, CompressionError] = error(CompressionError.LimitExceeded)
    let unsupported: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        try expect_equal(format.compress(data, -1), invalid)
        try expect_equal(format.compress(data, 10), invalid)
        try expect_equal(format.compress(data, max_bytes: -1), invalid)
        try expect_equal(format.compress(data, max_bytes: 0), limited)

        let method = format.compress
        try expect_equal(method(data, max_bytes: 1), limited)

    try expect_equal(compress(data, "invalid"), unsupported)
    try expect_equal(compress(data, "gzip", -1), invalid)
    try expect_equal(compress(data, "gzip", max_bytes: -1), invalid)
    try expect_equal(compress(data, "gzip", max_bytes: 0), limited)

test "compression default preparation retains supplied argument order":
    var log: List[String] = []
    let data = "data".to_bytes()
    let encoded = try compress(format: chosen(var log, "gzip"), supplied(var log, data))
    try expect_equal(log, ["format", "data"])
    try expect_equal((try decompress(encoded, "gzip")), data)
