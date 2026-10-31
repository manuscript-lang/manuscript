import expect_equal, expect_error, expect_false from "@std/test.ms"
import filesystem, FileSystemError from "@std/fs.ms"
import files, IoError from "@std/io.ms"
import control from "@std/process.ms"
import nanoseconds from "@std/time.ms"
import compress, decompress, CompressionError from "@std/archive.ms"
import pack, unpack, ArchiveEntry, ArchiveError from "@std/archive.ms"
import StringError from "@std/string.ms"
import Bytes from "@std/bytes.ms"

test "raw monotonic nanoseconds share the typed process uptime origin":
    let process = control()
    let before = try process.uptime()
    let reading = nanoseconds(process.monotonic_time())
    let after = try process.uptime()
    try expect_false(reading.compare(before) < 0 or reading.compare(after) > 0)

test "closed codec strings reject spelling changes with their domain errors":
    let data = "text".to_bytes()
    let normalization_error: Result[String, StringError] = error(
        StringError.InvalidInput
    )
    for form in ["nfc", "NFC ", ""]:
        try expect_equal("text".normalize(form), normalization_error)
    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        try expect_equal((try "text".normalize(form)), "text")

    let compression_error: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )

    for format in ["GZIP", "ZLIB", "DEFLATE", ""]:
        try expect_equal(compress(data, format, 0), compression_error)
        try expect_equal(decompress(data, format), compression_error)

    for format in ["gzip", "zlib", "deflate"]:
        for level in [0, 9]:
            try expect_equal(
                (
                    try compress(
                        data, format, level
                    ) | try decompress(format)
                ),
                data
            )

    let level_error: Result[Bytes, CompressionError] = error(
        CompressionError.InvalidInput
    )
    for level in [-1, 10]:
        try expect_equal(compress(data, "gzip", level), level_error)

    let pack_error: Result[Bytes, ArchiveError] = error(ArchiveError.Unsupported)
    let unpack_error: Result[List[ArchiveEntry], ArchiveError] = error(
        ArchiveError.Unsupported
    )

    for format in ["ZIP", "TAR", ""]:
        try expect_equal(pack([], format), pack_error)
        try expect_equal(unpack(data, format), unpack_error)

test "all ten string open modes are accepted and changed spellings are invalid":
    let fs = filesystem()
    let temporary = try fs.temporary("manuscript-open-modes-")

    for mode in ["r", "r+", "w", "wx", "w+", "wx+", "a", "ax", "a+", "ax+"]:
        let path = "{temporary.path()}/{mode}"
        if mode == "r" or mode == "r+":
            try fs.write_file(path, "", replace: false)

        let handle = try fs.open(path, mode, 384)
        let _fileinfo = try handle.stat()

    for mode in ["R", "rs", "w+x", " r", ""]:
        try expect_false(
            (
                (
                    try expect_error(
                        fs.open(
                            "{temporary.path()}/invalid", mode, 384
                        )
                    )
                ) != FileSystemError.InvalidInput
            )
        )

test "full byte counts positions EOF and stream aliases retain their contracts":
    let fs = filesystem()
    let temporary = try fs.temporary("manuscript-write-contract-")
    let path = "{temporary.path()}/data"
    let data = (try "é".repeat(40000)).to_bytes()
    var handle = try fs.open(path, "w+", 384)
    try handle.write_bytes(data)
    try expect_equal((try handle.stat()).size, 80000)
    try expect_false((try handle.read()).is_some())
    try expect_equal((try handle.read_at(80000)).length(), 0)
    try expect_equal((try handle.read_at(0, 80000)).length(), 65536)
    try expect_equal((try handle.read_file()).length(), 0)
    try expect_equal((try handle.seek(0, 0)), 0)
    try expect_equal((try handle.read()).get().length(), 65536)
    try expect_equal((try handle.read_file()).length(), 14464)

    let _count = try handle.seek(0, 0)
    try handle.append_file("XY")
    try expect_equal((try handle.read_at(0, 2)), "XY".to_bytes())
    try expect_equal((try handle.stat()).size, 80000)
    try handle.write_at(4, "ZZ")
    try expect_equal((try handle.seek(0, 1)), 2)

    var writer = handle.writer()
    try writer.write("AB")
    try writer.flush()
    try expect_equal((try handle.read_at(2, 4)), "ABZZ".to_bytes())

    var reader = handle.reader()
    writer.close()

    let closed_read: Result[Bytes, FileSystemError] = error(FileSystemError.Closed)
    try expect_equal(handle.read_at(0), closed_read)
    try expect_equal((try expect_error(reader.read())), IoError.Closed)
    try handle.close()

    let missing = "{temporary.path()}/missing"
    try expect_equal(
        (try expect_error(fs.open(missing, "r", 384))), FileSystemError.NotFound
    )
    try expect_equal((try expect_error(files().open(missing))), IoError.Unavailable)
