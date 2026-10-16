import {filesystem, FileSystemError} from "@std/fs.ms"
import {files, IoError} from "@std/io.ms"
import {control} from "@std/process.ms"
import {duration} from "@std/time.ms"
import {hmac, CryptoError} from "@std/crypto.ms"
import {compress, decompress, CompressionError} from "@std/compress.ms"
import {pack, unpack, ArchiveEntry, ArchiveError} from "@std/archive.ms"
import StringError from "@std/string.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "raw monotonic nanoseconds share the typed process uptime origin":
    let process = control()
    let before = value(process.uptime())
    let reading = duration(process.monotonic_time())
    let after = value(process.uptime())
    if reading.compare(before) < 0 or reading.compare(after) > 0: return panic(
        "monotonic units or origin"
    )

test "closed codec strings reject spelling changes with their domain errors":
    let data = "text".to_bytes()
    let hash_error: Result[Bytes, CryptoError] = error(CryptoError.Unsupported)
    for algorithm in ["SHA256", "sha-256", ""]:
        if hmac(key: data, data: data, algorithm: algorithm) != hash_error: return panic(
            "HMAC spelling"
        )
    for algorithm in ["sha256", "sha384", "sha512"]:
        if value(hmac(key: data, data: data, algorithm: algorithm)).is_empty(): return panic(
            "HMAC algorithm"
        )
    let normalization_error: Result[String, StringError] = error(
        StringError.InvalidInput
    )
    for form in ["nfc", "NFC ", ""]:
        if "text".normalize(form) != normalization_error: return panic(
            "normalization spelling"
        )
    for form in ["NFC", "NFD", "NFKC", "NFKD"]:
        if value("text".normalize(form)) != "text": return panic("normalization form")
    let compression_error: Result[Bytes, CompressionError] = error(
        CompressionError.Unsupported
    )

    for format in ["GZIP", "ZLIB", "DEFLATE", ""]:
        if compress(data: data, format: format, level: 0) != compression_error: return panic(
            "compression spelling"
        )
        if decompress(data: data, format: format) != compression_error: return panic(
            "decompression spelling"
        )

    for format in ["gzip", "zlib", "deflate"]:
        for level in [0, 9]:
            let encoded = value(compress(data: data, format: format, level: level))
            if value(decompress(data: encoded, format: format)) != data: return panic(
                "compression level boundary"
            )

    let level_error: Result[Bytes, CompressionError] = error(
        CompressionError.InvalidInput
    )
    for level in [-1, 10]:
        if compress(data: data, format: "gzip", level: level) != level_error: return panic(
            "compression level range"
        )
    let pack_error: Result[Bytes, ArchiveError] = error(ArchiveError.Unsupported)
    let unpack_error: Result[List[ArchiveEntry], ArchiveError] = error(
        ArchiveError.Unsupported
    )

    for format in ["ZIP", "TAR", ""]:
        if pack(entries: [], format: format) != pack_error: return panic(
            "archive pack spelling"
        )
        if unpack(data: data, format: format) != unpack_error: return panic(
            "archive unpack spelling"
        )

test "all ten string open modes are accepted and changed spellings are invalid":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-open-modes-")):
        for mode in ["r", "r+", "w", "wx", "w+", "wx+", "a", "ax", "a+", "ax+"]:
            let path = "{temporary.path()}/{mode}"
            if mode == "r" or mode == "r+":
                let created = value(
                    fs.write_file(
                        path: path,
                        data: "".to_bytes(),
                        replace: false
                    )
                )
            with handle = value(fs.open(path: path, flags: mode, mode: 384)):
                let info = value(handle.stat())

        for mode in ["R", "rs", "w+x", " r", ""]:
            match fs.open(path: "{temporary.path()}/invalid", flags: mode, mode: 384):
                ok(_): return panic("open spelling")
                error(cause):
                    if cause != FileSystemError.InvalidInput: return panic(
                        "open spelling error"
                    )

test "full byte counts positions EOF and stream aliases retain their contracts":
    let fs = filesystem()

    with temporary = value(fs.temporary("manuscript-write-contract-")):
        let path = "{temporary.path()}/data"
        let data = value("é".repeat(40000)).to_bytes()

        with handle = value(fs.open(path: path, flags: "w+", mode: 384)):
            value(handle.write(data))
            if value(handle.stat()).size != 80000: return panic(
                "write did not write all bytes"
            )
            if value(handle.read()).is_some(): return panic("sequential EOF")
            if value(handle.read_at(offset: 80000)).length() != 0: return panic(
                "positional EOF"
            )
            if value(handle.read_at(offset: 0, max_bytes: 80000)).length() != 65536: return panic(
                "chunk cap"
            )
            if value(handle.read_file()).length() != 0: return panic(
                "positional read moved sequential position"
            )
            if value(handle.seek(offset: 0, origin: 0)) != 0: return panic("seek start")
            if value(handle.read()).unwrap().length() != 65536: return panic(
                "default read chunk"
            )
            if value(handle.read_file()).length() != 14464: return panic(
                "remaining read"
            )

            let rewind = value(handle.seek(offset: 0, origin: 0))
            let overwritten = value(handle.append_file("XY".to_bytes()))
            if value(handle.read_at(offset: 0, max_bytes: 2)) != "XY".to_bytes(): return panic(
                "handle append repositioned"
            )
            if value(handle.stat()).size != 80000: return panic(
                "handle append extended"
            )

            value(handle.write_at(offset: 4, data: "ZZ".to_bytes()))
            if value(handle.seek(offset: 0, origin: 1)) != 2: return panic(
                "write_at moved position"
            )

            let writer = handle.writer()
            let delivered = value(writer.write("AB".to_bytes()))
            let flushed = value(writer.flush())
            if value(handle.read_at(offset: 2, max_bytes: 4)) != "ABZZ".to_bytes(): return panic(
                "writer position"
            )

            let reader = handle.reader()
            writer.close()
            let closed_read: Result[Bytes, FileSystemError] = error(
                FileSystemError.Closed
            )
            if handle.read_at(offset: 0) != closed_read: return panic(
                "adapter did not close handle"
            )

            match reader.read():
                ok(_): return panic("reader alias survived close")
                error(cause):
                    if cause != IoError.Closed: return panic(
                        "adapter Closed translation"
                    )

        let missing = "{temporary.path()}/missing"

        match fs.open(path: missing, flags: "r", mode: 384):
            ok(_): return panic("missing filesystem file opened")
            error(cause):
                if cause != FileSystemError.NotFound: return panic(
                    "filesystem missing mapping"
                )

        match files().open(missing):
            ok(_): return panic("missing io file opened")
            error(cause):
                if cause != IoError.Unavailable: return panic("io missing mapping")
