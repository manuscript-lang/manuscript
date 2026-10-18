import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import {files, IoError} from "@std/io.ms"
import {control} from "@std/process.ms"
import {duration} from "@std/time.ms"
import {hmac, CryptoError} from "@std/crypto.ms"
import {compress, decompress, CompressionError} from "@std/compress.ms"
import {pack, unpack, ArchiveEntry, ArchiveError} from "@std/archive.ms"
import StringError from "@std/string.ms"
import Bytes from "@std/bytes.ms"

test "raw monotonic nanoseconds share the typed process uptime origin":
    let process = control()
    let before = (process.uptime() | try expect_ok)
    let reading = duration(process.monotonic_time())
    let after = (process.uptime() | try expect_ok)
    (reading.compare(before) < 0 or reading.compare(after) > 0) | try expect_false

test "closed codec strings reject spelling changes with their domain errors":
    let data = "text".to_bytes()
    let hash_error: Result[Bytes, CryptoError] = error(CryptoError.Unsupported)
    for algorithm in ["SHA256", "sha-256", ""]:
        hmac(key: data, data: data, algorithm: algorithm) | try expect_equal(
            expected: hash_error
        )
    for algorithm in ["sha256", "sha384", "sha512"]:
        (hmac(key: data, data: data, algorithm: algorithm) | try expect_ok).is_empty() | try expect_false
    let normalization_error: Result[String, StringError] = error(
        StringError.InvalidInput
    )
    for form in ["nfc", "NFC ", ""]:
        "text".normalize(form) | try expect_equal(expected: normalization_error)
    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        "text".normalize(form) | try expect_ok | try expect_equal(expected: "text")
    let compression_error: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )

    for format in ["GZIP", "ZLIB", "DEFLATE", ""]:
        compress(data: data, format: format, level: 0) | try expect_equal(
            expected: compression_error
        )
        decompress(data: data, format: format) | try expect_equal(
            expected: compression_error
        )

    for format in ["gzip", "zlib", "deflate"]:
        for level in [0, 9]:
            let encoded = (
                compress(
                    data: data,
                    format: format,
                    level: level
                ) | try expect_ok
            )
            decompress(data: encoded, format: format) | try expect_ok | try expect_equal(
                expected: data
            )

    let level_error: Result[Bytes, CompressionError] = error(
        CompressionError.InvalidInput
    )
    for level in [-1, 10]:
        compress(data: data, format: "gzip", level: level) | try expect_equal(
            expected: level_error
        )
    let pack_error: Result[Bytes, ArchiveError] = error(ArchiveError.Unsupported)
    let unpack_error: Result[List[ArchiveEntry], ArchiveError] = error(
        ArchiveError.Unsupported
    )

    for format in ["ZIP", "TAR", ""]:
        pack(entries: [], format: format) | try expect_equal(expected: pack_error)
        unpack(data: data, format: format) | try expect_equal(expected: unpack_error)

test "all ten string open modes are accepted and changed spellings are invalid":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-open-modes-") | try expect_ok):
        for mode in ["r", "r+", "w", "wx", "w+", "wx+", "a", "ax", "a+", "ax+"]:
            let path = "{temporary.path()}/{mode}"
            if mode == "r" or mode == "r+":
                let created = (
                    fs.write_file(
                        path: path,
                        data: "".to_bytes(),
                        replace: false
                    ) | try expect_ok
                )
            with handle = (fs.open(path: path, flags: mode, mode: 384) | try expect_ok):
                let info = (handle.stat() | try expect_ok)

        for mode in ["R", "rs", "w+x", " r", ""]:
            match fs.open(path: "{temporary.path()}/invalid", flags: mode, mode: 384):
                ok(_): return fail("open spelling")
                error(cause):
                    try expect_equal(cause, FileSystemError.InvalidInput)

test "full byte counts positions EOF and stream aliases retain their contracts":
    let fs = filesystem()

    with temporary = (fs.temporary("manuscript-write-contract-") | try expect_ok):
        let path = "{temporary.path()}/data"
        let data = ("é".repeat(40000) | try expect_ok).to_bytes()

        with handle = (fs.open(path: path, flags: "w+", mode: 384) | try expect_ok):
            (handle.write(data) | try expect_ok)
            (handle.stat() | try expect_ok).size | try expect_equal(expected: 80000)
            (handle.read() | try expect_ok).is_some() | try expect_false
            (handle.read_at(offset: 80000) | try expect_ok).length() | try expect_equal(
                expected: 0
            )
            (handle.read_at(offset: 0, max_bytes: 80000) | try expect_ok).length() | try expect_equal(
                expected: 65536
            )
            (handle.read_file() | try expect_ok).length() | try expect_equal(
                expected: 0
            )
            handle.seek(offset: 0, origin: 0) | try expect_ok | try expect_equal(
                expected: 0
            )
            (
                (
                    handle.read() | try expect_ok
                ).unwrap().length() | try expect_equal(expected: 65536)
            )
            (handle.read_file() | try expect_ok).length() | try expect_equal(
                expected: 14464
            )
            let rewind = (handle.seek(offset: 0, origin: 0) | try expect_ok)
            let overwritten = (handle.append_file("XY".to_bytes()) | try expect_ok)
            handle.read_at(offset: 0, max_bytes: 2) | try expect_ok | try expect_equal(
                expected: "XY".to_bytes()
            )
            (handle.stat() | try expect_ok).size | try expect_equal(expected: 80000)
            (handle.write_at(offset: 4, data: "ZZ".to_bytes()) | try expect_ok)
            handle.seek(offset: 0, origin: 1) | try expect_ok | try expect_equal(
                expected: 2
            )
            let writer = handle.writer()
            let delivered = (writer.write("AB".to_bytes()) | try expect_ok)
            let flushed = (writer.flush() | try expect_ok)
            handle.read_at(offset: 2, max_bytes: 4) | try expect_ok | try expect_equal(
                expected: "ABZZ".to_bytes()
            )
            let reader = handle.reader()
            writer.close()
            let closed_read: Result[Bytes, FileSystemError] = error(
                FileSystemError.Closed
            )
            handle.read_at(offset: 0) | try expect_equal(expected: closed_read)

            match reader.read():
                ok(_): return fail("reader alias survived close")
                error(cause):
                    try expect_equal(cause, IoError.Closed)

        let missing = "{temporary.path()}/missing"

        match fs.open(path: missing, flags: "r", mode: 384):
            ok(_): return fail("missing filesystem file opened")
            error(cause):
                try expect_equal(cause, FileSystemError.NotFound)

        match files().open(missing):
            ok(_): return fail("missing io file opened")
            error(cause):
                try expect_equal(cause, IoError.Unavailable)
