import expect_equal from "@std/test/test.ms"
import (compress, decompress, CompressionFormat) from "@std/io/archive.ms"
import pack, unpack, ArchiveEntry, ArchiveLimits from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"
import from_bytes from "@std/io/streams.ms"
import read_line from "@std/io/io.ms"

test "compression formats roundtrip and enforce expanded byte budgets":
    let input = "hello hello hello".to_bytes()

    for format in ["gzip", "zlib", "deflate"]:
        let packed = try compress(input, format, 6)
        try expect_equal((try decompress(packed, format, 17)), input)

        let limited: Bytes! = error(
            Error(
                "compression: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        try expect_equal(decompress(packed, format, 16), limited)

    let unsupported: Bytes! = error(
        Error(
            "compression: operation not supported", kind: ErrorCategory.Unsupported
        )
    )
    try expect_equal(compress(input, "invalid", 6), unsupported)

    let malformed: Bytes! = error(
        Error("compression: invalid data", kind: ErrorCategory.InvalidData)
    )
    try expect_equal(decompress(input, "gzip"), malformed)

test "ZIP and TAR preserve entries and independently enforce archive limits":
    let entries = [
        ArchiveEntry("a.txt", "hello".to_bytes(), directory: false),
        ArchiveEntry("b.txt", "bye".to_bytes(), directory: false)
    ]

    for format in ["zip", "tar"]:
        let packed = try pack(entries, format)
        try expect_equal((try unpack(packed, format)), entries)

        let limited: List[ArchiveEntry]! = error(
            Error(
                "archive: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        try expect_equal(unpack(packed, format, ArchiveLimits(1)), limited)
        try expect_equal(
            unpack(packed, format, ArchiveLimits(max_entry_bytes: 4)), limited
        )
        try expect_equal(
            unpack(packed, format, ArchiveLimits(max_total_bytes: 7)), limited
        )

test "archives reject traversal paths":
    let invalid: Bytes! = error(
        Error("archive: invalid input", kind: ErrorCategory.InvalidInput)
    )

    for path in ["../escape", "/absolute"]:
        let entries = [ArchiveEntry(path, "".to_bytes(), directory: false)]
        try expect_equal(pack(entries, "zip"), invalid)

test "decompressed streams preserve lines across decoder output batches":
    let data = "archive line input\n".repeat(3500).get("").to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let packed = try format.compress(data)
        var stream = format.decompress_stream(from_bytes(packed, 32768))

        for i in 0..3500:
            let line = try read_line(stream)
            try expect_equal(line.get(""), "archive line input")

        try expect_equal((try read_line(stream)).is_none(), true)
        stream.close()
