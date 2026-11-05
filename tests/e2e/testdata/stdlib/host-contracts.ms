import expect_equal, expect_error, expect_false from "@std/test/test.ms"
import open, temporary, write_file from "@std/os/fs.ms"
import monotonic_time, uptime from "@std/os/system.ms"
import nanoseconds from "@std/os/time.ms"
import (
    compress,
    decompress,
    CompressionFormat,
    CompressOptions
) from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"

test "raw monotonic nanoseconds share the typed process uptime origin":
    let before = try uptime()
    let reading = nanoseconds(monotonic_time())
    let after = try uptime()
    try expect_false(reading.compare(before) < 0 or reading.compare(after) > 0)

test "closed normalization forms reject spelling changes with their domain errors":
    let data = "text".to_bytes()
    let normalization_error: String! = error(
        Error("string: invalid input", kind: "EINVAL")
    )
    for form in ["nfc", "NFC ", ""]:
        try expect_equal("text".normalize(form), normalization_error)
    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        try expect_equal((try "text".normalize(form)), "text")
    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        for level in [0, 9]:
            try expect_equal(
                (
                    try compress(
                        data, format, CompressOptions(level: level)
                    ) | try decompress(format)
                ),
                data
            )

    let level_error: Bytes! = error(Error("compression: invalid input", kind: "EINVAL"))
    for level in [-1, 10]:
        try expect_equal(
            compress(
                data, CompressionFormat.Gzip, CompressOptions(level: level)
            ),
            level_error
        )

test "all ten string open modes are accepted and changed spellings are invalid":
    let temporary = try temporary("manuscript-open-modes-")

    for mode in ["r", "r+", "w", "wx", "w+", "wx+", "a", "ax", "a+", "ax+"]:
        let path = "{temporary.path()}/{mode}"
        if mode == "r" or mode == "r+":
            try write_file(path, "", replace: false).wait()

        let handle = try open(path, mode, 384)
        let _fileinfo = try handle.stat()

    let invalid = "{temporary.path()}/invalid"

    for mode in ["R", "rs", "w+x", " r", ""]:
        let refused = try expect_error(open(invalid, mode, 384))
        try expect_equal(refused.kind, "EINVAL")
        try expect_equal(refused.message, "filesystem: invalid input: {invalid}")

test "full byte counts positions EOF and stream aliases retain their contracts":
    let temporary = try temporary("manuscript-write-contract-")
    let path = "{temporary.path()}/data"
    let data = (try "é".repeat(40000)).to_bytes()
    var handle = try open(path, "w+", 384)
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

    var writer = try handle.writer()
    try writer.write("AB".to_bytes())
    try writer.flush().wait()
    try expect_equal((try handle.read_at(2, 4)), "ABZZ".to_bytes())

    var reader = try handle.reader()
    try writer.close()
    try expect_equal((try handle.read_at(2, 4)), "ABZZ".to_bytes())
    try handle.close()

    let closed_read: Bytes! = error(
        Error("filesystem: resource is closed", kind: "EBADF")
    )
    try expect_equal(handle.read_at(0), closed_read)
    try reader.close()

    let missing = "{temporary.path()}/missing"
    let absent = try expect_error(open(missing, "r", 384))
    try expect_equal(absent.kind, "ENOENT")
    try expect_equal(
        absent.message, "filesystem: file or directory not found: {missing}"
    )
