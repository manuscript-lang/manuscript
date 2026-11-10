import (
    expect_equal, expect_error from "@std/test/test.ms",
    compress, decompress, CompressionFormat from "@std/io/archive.ms",
    pack, unpack, ArchiveEntry, ArchiveFormat, ArchiveOptions from "@std/io/archive.ms",
    Bytes from "@std/bytes.ms",
    hex_decode from "@std/data/encoding.ms",
)

test "compression formats roundtrip and enforce expanded byte budgets":
    let input = "hello hello hello".to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let packed = try compress(input, format)
        try expect_equal((try decompress(packed, format, 17)), input)

        let limited: Bytes! = error(
            Error("compression: limit exceeded", kind: "EOVERFLOW")
        )
        try expect_equal(decompress(packed, format, 16), limited)

    let malformed: Bytes! = error(Error("compression: invalid data", kind: "EBADMSG"))
    try expect_equal(decompress(input, CompressionFormat.Gzip), malformed)

test "ZIP and TAR preserve entries and independently enforce archive limits":
    let entries = [
        ArchiveEntry("a.txt", "hello".to_bytes(), directory: false),
        ArchiveEntry("b.txt", "bye".to_bytes(), directory: false)
    ]

    for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
        let packed = try pack(entries, format)
        try expect_equal((try unpack(packed, format)), entries)

        let limited: List[ArchiveEntry]! = error(
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
    let invalid: Bytes! = error(Error("archive: invalid input", kind: "EINVAL"))

    for path in ["../escape", "/absolute"]:
        let entries = [ArchiveEntry(path, "".to_bytes(), directory: false)]
        try expect_equal(pack(entries, ArchiveFormat.Zip), invalid)

test "ZIP unpack verifies a zero stored checksum":
    let forged = hex_decode(
        "504b03041400000000000000210000000000050000000500000005000000662e74787468656c6c6f504b0102140314000000000000002100000000000500000005000000050000000000000000000000800100000000662e747874504b0506000000000100010033000000280000000000",
        none
    ).get(Bytes([]))
    let failure = try expect_error(unpack(forged, ArchiveFormat.Zip))
    try expect_equal(failure.kind.get(""), "EBADMSG")
