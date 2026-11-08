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
import Bytes, BytesBuilder, join from "@std/bytes.ms"
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

// Sends its bytes once, then fails every read, so a reader that waits for data it should have refused sees `EIO`.
type HeaderThenFail:
    head: Bytes
    sent: Bool

impl Source[Bytes] for HeaderThenFail:
    var fn next() Bytes?!:
        if self.sent: return error(Error("pulled past the header", kind: "EIO"))

        self.sent = true
        return ok(self.head.clone())

    var fn close() Unit!:
        return ok(unit)

test "tar entries refuse an oversized member from its header":
    let archive = try pack(
        [
            ArchiveEntry(
                "f", "x".repeat(4000).get("").to_bytes(), directory: false
            )
        ],
        ArchiveFormat.Tar
    )
    let header = try archive.slice(0, 512)
    let entry = read_entries(
        ReadStream[Bytes](HeaderThenFail(header.clone(), false)),
        ArchiveOptions(max_entry_bytes: 10)
    )
    try expect_equal(entry.err().kind, "EOVERFLOW")

    let total = read_entries(
        ReadStream[Bytes](HeaderThenFail(header.clone(), false)),
        ArchiveOptions(max_bytes: 10)
    )
    try expect_equal(total.err().kind, "EOVERFLOW")

test "tar entries reject a base-256 size that overflows as invalid":
    let archive = try pack(
        [ArchiveEntry("f", "hi".to_bytes(), directory: false)], ArchiveFormat.Tar
    )
    var bad = BytesBuilder()

    for index in 0..archive.length():
        var byte = archive[index]
        if index >= 124 and index < 136: byte = 255
        bad.append(byte)

    let got = read_entries(chunked(bad.build(), 4096))
    try expect_equal(got.err().kind, "EBADMSG")

test "decompressed streams reject bytes after the payload as decompress does":
    let text = "tail check ".repeat(50).get("").to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let packed = try compress(text.clone(), format)
        let junk = packed.concat("junk".to_bytes())
        try expect_equal((decompress(junk.clone(), format)).err().kind, "EBADMSG")

        for size in [1, 7, 4096]:
            let got = read_all(decompressed(chunked(junk.clone(), size), format))
            try expect_equal(got.err().kind, "EBADMSG")

// One member of a tar archive: a file's header and data block, or a directory's header.
fn member(path: String, directory: Bool) Bytes!:
    let data = if directory: "".to_bytes() else: "x".to_bytes()
    let archive = try pack([ArchiveEntry(path, data, directory)], ArchiveFormat.Tar)
    return archive.slice(0, if directory: 512 else: 1024)

// Paths ending in `/` are directories.
fn members(paths: List[String]) Bytes!:
    var archive = join([])

    for path in paths:
        let directory = path.ends_with("/")
        let name = if directory: path.take(path.length() - 1) else: path
        archive = archive.concat(try member(name, directory))

    var end = BytesBuilder()
    for index in 0..1024:
        end.append(0)
    return ok(archive.concat(end.build()))

test "tar entries reject duplicate and conflicting paths as unpack does":
    let cases = [
        ["same.txt", "same.txt"], ["a/", "a"], ["a", "a/b"], ["a/b", "a"],
        ["a", "a/b/c/"]
    ]

    for paths in cases:
        let archive = try members(paths)
        let expected = unpack(archive.clone(), ArchiveFormat.Tar)
        try expect_equal(expected.is_error(), true)

        for size in [1, 512, 700, 4096]:
            let got = read_entries(chunked(archive.clone(), size))
            try expect_equal(got.err().kind, expected.err().kind)

test "tar entries accept distinct paths and sibling directories":
    let archive = try members(["a/", "a/b", "a/c/", "a/c/d", "e"])
    let expected = try unpack(archive.clone(), ArchiveFormat.Tar)
    try expect_equal(try read_entries(chunked(archive, 700)), expected)

// A ustar header block with a valid checksum.
fn header(name: String, size: Int, flag: Int) Bytes:
    var block: List[Int] = []
    for index in 0..512:
        block.append(0)

    let label = name.to_bytes()
    for index in 0..label.length():
        block[index] = label.get(index, 0).to_int()

    var left = size

    for index in 0..11:
        block[134 - index] = 48 + left % 8
        left = left / 8

    block[156] = flag

    let magic = "ustar".to_bytes()
    for index in 0..5:
        block[257 + index] = magic.get(index, 0).to_int()
    block[263] = 48
    block[264] = 48
    for index in 148..156:
        block[index] = 32

    var sum = 0
    for byte in block:
        sum += byte

    var rest = sum

    for index in 0..6:
        block[153 - index] = 48 + rest % 8
        rest = rest / 8

    block[154] = 0
    block[155] = 32

    var out = BytesBuilder()
    for byte in block:
        out.append(byte.to_uint8().get(0))
    return out.build()

// Zero-pads `data` to a whole 512-byte block.
fn padded(data: Bytes) Bytes:
    var out = BytesBuilder()
    out.append_bytes(data.clone())
    for index in 0..(512 - data.length() % 512) % 512:
        out.append(0)
    return out.build()

test "tar entries frame members by a PAX size override as unpack does":
    var archive = BytesBuilder()
    let records = "9 size=1\n".to_bytes()
    archive.append_bytes(header("pax", records.length(), 120))
    archive.append_bytes(padded(records))
    archive.append_bytes(header("f", 0, 48))
    archive.append_bytes(padded("x".to_bytes()))
    for index in 0..1024:
        archive.append(0)

    let bytes = archive.build()
    let expected = try unpack(bytes.clone(), ArchiveFormat.Tar)
    try expect_equal(expected.length(), 1)
    try expect_equal(expected[0].data, "x".to_bytes())
    for size in [1, 512, 1536, 4096]:
        try expect_equal(try read_entries(chunked(bytes.clone(), size)), expected)

// Replaces the byte at `at` with `value`.
fn with_byte(data: Bytes, at: Int, value: Int) Bytes:
    var out = BytesBuilder()
    out.append_bytes(data.slice(0, at).get("".to_bytes()))
    out.append(value.to_uint8().get(0))
    out.append_bytes(data.slice(at + 1, data.length()).get("".to_bytes()))
    return out.build()

// "ok" with the entries' paths and sizes, or the error kind.
fn outcome(entries: List[ArchiveEntry]!) String:
    if entries.is_error(): return entries.err().kind.get("none")

    var text = "ok"
    for entry in entries.get():
        text += " {entry.path}:{entry.data.length()}:{entry.directory}"
    return text

test "tar entries and unpack agree on corrupted and truncated archives":
    let archive = try pack(sample(), ArchiveFormat.Tar)
    var cases: List[Bytes] = []

    // Header fields (name, size, checksum, type) and data bytes of each member, set to boundary values.
    for at in [0, 1, 100, 124, 125, 130, 135, 148, 155, 156, 257, 512, 700, 1024, 1536, 2048]:
        for value in [0, 55, 56, 120, 255]:
            cases.append(with_byte(archive.clone(), at, value))

    // Truncations, including mid-block and exactly on member boundaries.
    for cut in [0, 1, 511, 512, 513, 1024, 1500, 2047, 2048, 2561, 3000]:
        cases.append(archive.slice(0, cut).get("".to_bytes()))

    for index in 0..cases.length():
        let expected = outcome(unpack(cases[index].clone(), ArchiveFormat.Tar))

        for size in [1, 97, 512, 4096]:
            let got = outcome(read_entries(chunked(cases[index].clone(), size)))
            if got != expected: return fail(
                "case {index}, chunk {size}: unpack {expected}, stream {got}"
            )
