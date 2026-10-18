import {compress, decompress, CompressionError} from "@std/compress.ms"
import {pack, unpack, ArchiveEntry, ArchiveLimits, ArchiveError} from "@std/archive.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"

test "compression formats roundtrip and enforce expanded byte budgets":
    let input = "hello hello hello".to_bytes()

    for format in ["gzip", "zlib", "deflate"]:
        let packed = try compress(input, format, 6)
        if ((try decompress(packed, format, 17)) != input): return panic(
            "compression roundtrip"
        )

        let limited: Result[Bytes, CompressionError] = error(
            CompressionError.LimitExceeded
        )
        if (decompress(packed, format, 16) != limited): return panic(
            "expanded byte budget"
        )

    let unsupported: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )
    if compress(input, "invalid", 6) != unsupported: return panic("unsupported format")

    let malformed: Result[Bytes, CompressionError] = error(CompressionError.InvalidData)
    if decompress(input, "gzip") != malformed: return panic("invalid compressed data")

test "ZIP and TAR preserve entries and independently enforce archive limits":
    let entries = [
        ArchiveEntry("a.txt", "hello".to_bytes(), directory: false),
        ArchiveEntry("b.txt", "bye".to_bytes(), directory: false)
    ]

    for format in ["zip", "tar"]:
        let packed = try pack(entries, format)
        if (try unpack(packed, format)) != entries: return panic("archive roundtrip")

        let limited: Result[List[ArchiveEntry], ArchiveError] = error(
            ArchiveError.LimitExceeded
        )
        if (unpack(packed, format, ArchiveLimits(1)) != limited): return panic(
            "entry count"
        )
        if (unpack(packed, format, ArchiveLimits(max_entry_bytes: 4)) != limited): return panic(
            "entry bytes"
        )
        if (unpack(packed, format, ArchiveLimits(max_total_bytes: 7)) != limited): return panic(
            "total bytes"
        )

test "archives reject traversal paths":
    let invalid: Result[Bytes, ArchiveError] = error(ArchiveError.InvalidInput)

    for path in ["../escape", "/absolute"]:
        let entries = [ArchiveEntry(path, "".to_bytes(), directory: false)]
        if pack(entries, "zip") != invalid: return panic("unsafe archive path")
