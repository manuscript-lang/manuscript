import expect_equal from "@std/test/test.ms"
import HashAlgorithm, sha256, sha384, sha512 from "@std/crypto.ms"
import (CompressionFormat, compress, decompress) from "@std/io/archive.ms"
import (
    ArchiveFormat,
    pack,
    unpack,
    ArchiveEntry,
    ArchiveLimits
) from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"

fn digest(algorithm: HashAlgorithm, data: Bytes) Bytes:
    return algorithm.digest(data)

fn call_digest[T](operation: fn(Bytes) T, data: Bytes) T:
    return operation(data)

fn bounded_compression(operation: fn(Bytes, Int, Int?) Bytes!, data: Bytes) Bytes!:
    return operation(data, 6, 1024)

test "typed SHA selectors match their algorithms and retain bound operations":
    let data = "abc".to_bytes()
    try expect_equal(digest(HashAlgorithm.Sha256, data), sha256(data))
    try expect_equal(digest(HashAlgorithm.Sha384, data), sha384(data))
    try expect_equal(digest(HashAlgorithm.Sha512, data), sha512(data))

    let stored = HashAlgorithm.Sha384.digest
    try expect_equal(stored(data), sha384(data))
    try expect_equal(call_digest(stored, data), sha384(data))

    let key = "key".to_bytes()
    for algorithm in [HashAlgorithm.Sha256, HashAlgorithm.Sha384, HashAlgorithm.Sha512]:
        try expect_equal(
            (try algorithm.hmac(key, data)).length(), (algorithm.digest(data).length())
        )

    let hmac_operation = HashAlgorithm.Sha512.hmac
    try expect_equal(
        (try hmac_operation(key, data)), (try HashAlgorithm.Sha512.hmac(key, data))
    )

test "typed compression preserves bytes limits errors and optional arguments":
    let data = "typed codecs typed codecs".to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        let name = match format:
            Gzip: "gzip"
            Zlib: "zlib"
            Deflate: "deflate"

        for level in [0, 9]:
            let encoded = try format.compress(data, level)
            try expect_equal(encoded, (try compress(data, name, level, none)))
            try expect_equal((try format.decompress(encoded, none)), data)
            try expect_equal((try format.decompress(encoded, data.length())), data)

            let limited: Bytes! = error(
                Error(
                    "compression: limit exceeded", kind: ErrorCategory.LimitExceeded
                )
            )
            try expect_equal(format.decompress(encoded, data.length() - 1), limited)

        let invalid: Bytes! = error(
            Error(
                "compression: invalid input", kind: ErrorCategory.InvalidInput
            )
        )
        try expect_equal(format.compress(data, -1), invalid)
        try expect_equal(format.compress(data, 6, -1), invalid)

        let zero: Bytes! = error(
            Error(
                "compression: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        try expect_equal(format.compress(data, 6, 0), zero)

    let stored = CompressionFormat.Gzip.compress
    let encoded = try bounded_compression(stored, data)
    let decoder = CompressionFormat.Gzip.decompress
    try expect_equal((try decoder(encoded)), data)
    try expect_equal((try decompress(encoded, "gzip")), data)

    let malformed: Bytes! = error(
        Error("compression: invalid data", kind: ErrorCategory.InvalidData)
    )
    try expect_equal(CompressionFormat.Gzip.decompress(data), malformed)

test "typed archives retain entry limits validation and existing string calls":
    let entries = [ArchiveEntry("file.txt", "data".to_bytes(), false)]

    for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
        let name = match format:
            Zip: "zip"
            Tar: "tar"

        let encoded = try format.pack(entries)
        try expect_equal(encoded, (try pack(entries, name)))
        try expect_equal((try format.unpack(encoded)), entries)
        try expect_equal((try format.unpack(encoded, none)), entries)
        try expect_equal((try unpack(encoded, name)), entries)

        let limited: List[ArchiveEntry]! = error(
            Error(
                "archive: limit exceeded", kind: ErrorCategory.LimitExceeded
            )
        )
        try expect_equal(format.unpack(encoded, ArchiveLimits(0)), limited)

        let invalid: Bytes! = error(
            Error(
                "archive: invalid input", kind: ErrorCategory.InvalidInput
            )
        )
        try expect_equal(
            format.pack([ArchiveEntry("../escape", "".to_bytes(), false)]), invalid
        )
        try expect_equal(format.pack(entries, -1), invalid)

    let stored = ArchiveFormat.Zip.pack
    let unpacker = ArchiveFormat.Zip.unpack
    try expect_equal(
        (stored(entries, none) | try | unpacker(ArchiveLimits()) | try), entries
    )
