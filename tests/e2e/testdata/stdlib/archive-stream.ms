import expect_equal, fail from "@std/test/test.ms"
import (
    compressed,
    decompressed,
    tar_entries,
    pack,
    unpack,
    compress,
    decompress,
    ArchiveEntry,
    ArchiveFormat,
    ArchiveOptions,
    CompressionFormat
) from "@std/io/archive.ms"
import Bytes, join from "@std/bytes.ms"
import ReadStream, Source from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

// Hands out the chunks in order, then ends.
type Chunks:
    data: Bytes
    size: Int
    at: Int

impl Source[Bytes] for Chunks:
    var fn next() Bytes?!:
        if self.at >= self.data.length(): return ok(none)

        var end = self.at + self.size
        if end > self.data.length(): end = self.data.length()

        let piece = try self.data.slice(self.at, end)
        self.at = end
        return ok(piece)

    var fn close() Unit!:
        return ok(unit)

fn chunked(data: Bytes, size: Int) ReadStream[Bytes]:
    return ReadStream[Bytes](Chunks(data, size, 0))

fn read_all(input: ReadStream[Bytes]) Bytes!:
    var source = input
    var out: List[Bytes] = []

    while true:
        let next = try source.next()

        if let data = next:
            out.append(data)
        else:
            break

    return ok(join(out))

test "compression streams round trip all formats under every chunk size":
    let text = "compress me compress me compress me".to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        for size in [1, 5, 64]:
            let packed = try read_all(compressed(chunked(text.clone(), size), format))
            if (try decompress(packed.clone(), format)) != text: return fail(
                "whole decode, size {size}"
            )

            let restored = try read_all(
                decompressed(chunked(packed.clone(), size), format)
            )
            if restored != text: return fail("stream round trip, size {size}")

test "decompressed streams preserve lines across decoder output batches":
    let data = "archive line input\n".repeat(3500).get("").to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let packed = try compress(data.clone(), format)
        var rows = lines(decompressed(chunked(packed, 32768), format))
        var count = 0

        while true:
            let next = try rows.next()

            if let line = next:
                try expect_equal(line, "archive line input")
                count += 1
            else:
                break

        try expect_equal(count, 3500)

test "decompression budget, garbage and level are errors":
    let text = "compress me compress me compress me".to_bytes()
    let packed = try read_all(
        compressed(chunked(text.clone(), 7), CompressionFormat.Gzip)
    )
    let limited = read_all(decompressed(chunked(packed, 7), CompressionFormat.Gzip, 4))
    try expect_equal(limited.err().kind, "EOVERFLOW")

    let garbage = read_all(
        decompressed(chunked(text.clone(), 7), CompressionFormat.Gzip)
    )
    try expect_equal(garbage.err().kind, "EBADMSG")

    let whole = try compress(text.clone(), CompressionFormat.Gzip)
    let head = try whole.slice(0, 12)
    let truncated = read_all(decompressed(chunked(head, 5), CompressionFormat.Gzip))
    try expect_equal(truncated.err().kind, "EBADMSG")

    let level = read_all(compressed(chunked(text, 7), CompressionFormat.Gzip, 10))
    try expect_equal(level.err().kind, "EINVAL")

fn sample() List[ArchiveEntry]:
    return [
        ArchiveEntry("dir", "".to_bytes(), directory: true),
        ArchiveEntry("dir/a.txt", "alpha".to_bytes(), directory: false),
        ArchiveEntry(
            "big.bin", "x".repeat(1300).get("").to_bytes(), directory: false
        ),
        ArchiveEntry("empty", "".to_bytes(), directory: false)
    ]

fn read_entries(
    input: ReadStream[Bytes],
    options: ArchiveOptions = ArchiveOptions()
) List[ArchiveEntry]!:
    var entries = tar_entries(input, options)
    var out: List[ArchiveEntry] = []

    while true:
        let next = try entries.next()

        if let entry = next:
            out.append(entry)
        else:
            break

    return ok(out)

test "tar entries match unpack under every chunk size":
    let archive = try pack(sample(), ArchiveFormat.Tar)
    let expected = try unpack(archive.clone(), ArchiveFormat.Tar)

    for size in [1, 100, 511, 512, 513, 4096]:
        let got = try read_entries(chunked(archive.clone(), size))
        if got != expected: return fail("chunk size {size}")

test "tar entries enforce limits and report truncation":
    let archive = try pack(sample(), ArchiveFormat.Tar)
    let few = read_entries(
        chunked(archive.clone(), 700), ArchiveOptions(max_entries: 2)
    )
    try expect_equal(few.err().kind, "EOVERFLOW")

    let big = read_entries(
        chunked(archive.clone(), 700), ArchiveOptions(max_entry_bytes: 100)
    )
    try expect_equal(big.err().kind, "EOVERFLOW")

    let total = read_entries(
        chunked(archive.clone(), 700), ArchiveOptions(max_bytes: 1000)
    )
    try expect_equal(total.err().kind, "EOVERFLOW")

    let cut = read_entries(chunked(archive.slice(0, 1000).get("".to_bytes()), 300))
    try expect_equal(cut.err().kind, "EBADMSG")
