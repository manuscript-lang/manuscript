import expect_equal, expect_error, expect_false from "@std/test/test.ms"
import OpenMode, OpenOptions, Seek, open, temporary, write_file from "@std/os/fs.ms"
import (
    compress,
    decompress,
    CompressionFormat,
    CompressOptions
) from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"

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

test "every open mode with and without exclusive creation opens":
    let temporary = try temporary("manuscript-open-modes-")
    let modes = [
        OpenMode.Read, OpenMode.ReadWrite, OpenMode.Write, OpenMode.WriteRead,
        OpenMode.Append, OpenMode.AppendRead
    ]

    for index in 0..modes.length():
        let mode = modes[index]
        let path = "{temporary.path()}/{index}"
        if index < 2:
            try write_file(path, "", replace: false).wait()

        let handle = try open(path, mode, OpenOptions(permissions: 384))
        let _fileinfo = try handle.stat()

    // Exclusive creation fails on an existing file and succeeds on a new one.
    let existing = "{temporary.path()}/2"
    let refused = try expect_error(
        open(existing, OpenMode.Write, OpenOptions(exclusive: true))
    )
    try expect_equal(refused.kind, "EEXIST")

    let fresh = try open(
        "{temporary.path()}/fresh", OpenMode.AppendRead, OpenOptions(exclusive: true)
    )
    let _fresh_info = try fresh.stat()

test "full byte counts positions EOF and stream aliases retain their contracts":
    let temporary = try temporary("manuscript-write-contract-")
    let path = "{temporary.path()}/data"
    let data = (try "é".repeat(40000)).to_bytes()
    var handle = try open(path, OpenMode.WriteRead, OpenOptions(permissions: 384))
    try handle.write(data)
    try expect_equal((try handle.stat()).size, 80000)
    try expect_false((try handle.read()).is_some())
    try expect_equal((try handle.read_at(80000)).length(), 0)
    try expect_equal((try handle.read_at(0, 80000)).length(), 65536)
    try expect_equal((try handle.read_file()).length(), 0)
    try expect_equal((try handle.seek(0, Seek.Start)), 0)
    try expect_equal((try handle.read()).get().length(), 65536)
    try expect_equal((try handle.read_file()).length(), 14464)

    let _count = try handle.seek(0, Seek.Start)
    try handle.write("XY")
    try expect_equal((try handle.read_at(0, 2)), "XY".to_bytes())
    try expect_equal((try handle.stat()).size, 80000)
    try handle.write_at(4, "ZZ")
    try expect_equal((try handle.seek(0, Seek.Current)), 2)

    var writer = try handle.writer()
    try writer.write("AB".to_bytes())
    try writer.flush()
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
    let absent = try expect_error(
        open(missing, OpenMode.Read, OpenOptions(permissions: 384))
    )
    try expect_equal(absent.kind, "ENOENT")
    try expect_equal(
        absent.message, "filesystem: file or directory not found: {missing}"
    )
