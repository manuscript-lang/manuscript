import {compress, decompress, CompressionFormat, CompressionError} from "@std/compress.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"

fn forwarded[T](item: T) T: item

fn supplied(log: List[String], data: Bytes) Bytes:
    log.append("data")
    return data

fn chosen(log: List[String], format: String) String:
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
        index += 1
        let expected = try compress(data, name, 6)
        if (try alias(data, name)) != expected: return panic(
            "stored function default bytes"
        )
        if (try compress(data, name, max_bytes: none)) != expected: return panic(
            "explicit none budget"
        )

        let method = format.compress
        let copied = method
        if (try copied(data)) != expected: return panic("bound format default bytes")
        if (try method(data, level: 6)) != expected: return panic(
            "explicit bound level"
        )
        if (try format.compress(data, max_bytes: expected.length())) != expected: return panic(
            "exact output budget"
        )
        if (try format.decompress(expected)) != data: return panic("typed round trip")
        if (try decompress(expected, name)) != data: return panic("string round trip")

        for level in [0, 9]:
            let output = try format.compress(data, level)
            if (try decompress(output, name)) != data: return panic(
                "explicit level endpoints"
            )

        let full = forwarded(method)
        let free = forwarded(compress)
        if (try free(data, name, 6, none)) != expected: return panic(
            "forwarded string call"
        )
        if (try full(data, 6, none)) != expected: return panic(
            "full-signature forwarded call"
        )

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
        if format.compress(data, -1) != invalid: return panic(
            "native default sentinel leaked"
        )
        if format.compress(data, 10) != invalid: return panic("invalid explicit level")
        if format.compress(data, max_bytes: -1) != invalid: return panic(
            "negative budget"
        )
        if format.compress(data, max_bytes: 0) != limited: return panic(
            "zero output budget"
        )

        let method = format.compress
        if method(data, max_bytes: 1) != limited: return panic("small output budget")

    if compress(data, "invalid") != unsupported: return panic(
        "format validation changed"
    )
    if compress(data, "gzip", -1) != invalid: return panic(
        "string level validation changed"
    )
    if compress(data, "gzip", max_bytes: -1) != invalid: return panic(
        "string budget validation changed"
    )
    if compress(data, "gzip", max_bytes: 0) != limited: return panic(
        "string output budget changed"
    )

test "compression default preparation retains supplied argument order":
    let log: List[String] = []
    let data = "data".to_bytes()
    let encoded = try compress(format: chosen(log, "gzip"), data: supplied(log, data))
    if log != ["format", "data"]: return panic("default reordered supplied arguments")
    if (try decompress(encoded, "gzip")) != data: return panic(
        "ordered compression output"
    )
