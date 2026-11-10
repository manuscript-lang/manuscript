import expect_equal from "@std/test/test.ms"
import (compress, decompress, CompressionFormat) from "@std/io/archive.ms"
import (
    pack,
    unpack,
    ArchiveEntry,
    ArchiveFormat,
    ArchiveOptions
) from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"

test "compression formats roundtrip and enforce expanded byte budgets":
    input := "hello hello hello".to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        packed := try compress(input, format)
        try expect_equal((try decompress(packed, format, 17)), input)

        limited: Bytes! = error(Error("compression: limit exceeded", kind: "EOVERFLOW"))
        try expect_equal(decompress(packed, format, 16), limited)

    malformed: Bytes! = error(Error("compression: invalid data", kind: "EBADMSG"))
    try expect_equal(decompress(input, CompressionFormat.Gzip), malformed)

test "ZIP and TAR preserve entries and independently enforce archive limits":
    entries := [
        ArchiveEntry("a.txt", "hello".to_bytes(), directory: false),
        ArchiveEntry("b.txt", "bye".to_bytes(), directory: false)
    ]

    for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
        packed := try pack(entries, format)
        try expect_equal((try unpack(packed, format)), entries)

        limited: List[ArchiveEntry]! = error(
            Error("archive: limit exceeded", kind: "EOVERFLOW")
        )
        try expect_equal(
            unpack(packed, format, ArchiveOptions(max_entries: 1)), limited
        )
        try expect_equal(
            unpack(packed, format, ArchiveOptions(max_entry_bytes: 4)), limited
        )
        try expect_equal(unpack(packed, format, ArchiveOptions(max_bytes: 7)), limited)

test "archives reject traversal paths":
    invalid: Bytes! = error(Error("archive: invalid input", kind: "EINVAL"))

    for path in ["../escape", "/absolute"]:
        entries := [ArchiveEntry(path, "".to_bytes(), directory: false)]
        try expect_equal(pack(entries, ArchiveFormat.Zip), invalid)
