import {expect_equal, expect_false, expect_ok} from "@std/testing.ms"
import {compress, decompress, CompressionError} from "@std/compress.ms"
import {pack, unpack, ArchiveEntry, ArchiveLimits, ArchiveError} from "@std/archive.ms"
import Bytes from "@std/bytes.ms"

test "compression formats roundtrip and enforce expanded byte budgets":
    let input = "hello hello hello".to_bytes()

    for format in ["gzip", "zlib", "deflate"]:
        let packed = (compress(data: input, format: format, level: 6) | try expect_ok)
        decompress(data: packed, format: format, max_bytes: 17) | try expect_ok | try expect_equal(
            expected: input
        )
        let limited: Result[Bytes, CompressionError] = error(
            CompressionError.LimitExceeded
        )
        decompress(data: packed, format: format, max_bytes: 16) | try expect_equal(
            expected: limited
        )

    let unsupported: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )
    compress(data: input, format: "invalid", level: 6) | try expect_equal(
        expected: unsupported
    )
    let malformed: Result[Bytes, CompressionError] = error(CompressionError.InvalidData)
    decompress(data: input, format: "gzip") | try expect_equal(expected: malformed)

test "ZIP and TAR preserve entries and independently enforce archive limits":
    let entries = [
        ArchiveEntry(path: "a.txt", data: "hello".to_bytes(), directory: false),
        ArchiveEntry(path: "b.txt", data: "bye".to_bytes(), directory: false)
    ]

    for format in ["zip", "tar"]:
        let packed = (pack(entries: entries, format: format) | try expect_ok)
        unpack(data: packed, format: format) | try expect_ok | try expect_equal(
            expected: entries
        )
        let limited: Result[List[ArchiveEntry], ArchiveError] = error(
            ArchiveError.LimitExceeded
        )
        (
            (
                unpack(
                    data: packed,
                    format: format,
                    limits: ArchiveLimits(max_entries: 1)
                ) != limited
            )
        ) | try expect_false
        (
            (
                unpack(
                    data: packed,
                    format: format,
                    limits: ArchiveLimits(max_entry_bytes: 4)
                ) != limited
            )
        ) | try expect_false
        (
            (
                unpack(
                    data: packed,
                    format: format,
                    limits: ArchiveLimits(max_total_bytes: 7)
                ) != limited
            )
        ) | try expect_false

test "archives reject traversal paths":
    let invalid: Result[Bytes, ArchiveError] = error(ArchiveError.InvalidInput)

    for path in ["../escape", "/absolute"]:
        let entries = [ArchiveEntry(path: path, data: "".to_bytes(), directory: false)]
        pack(entries: entries, format: "zip") | try expect_equal(expected: invalid)
