import expect_equal from "@std/test/test.ms"
import HashAlgorithm, sha256, sha384, sha512 from "@std/crypto.ms"
import (
    CompressionFormat,
    CompressOptions,
    compress,
    decompress,
    ArchiveFormat,
    pack,
    unpack,
    ArchiveEntry,
    ArchiveOptions
) from "@std/io/archive.ms"
import Bytes from "@std/bytes.ms"

fn digest(algorithm: HashAlgorithm, data: Bytes) Bytes:
    return algorithm.digest(data)

fn call_digest[T](operation: fn(Bytes) T, data: Bytes) T:
    return operation(data)

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

test "typed compression preserves bytes limits and errors":
    let data = "typed codecs typed codecs".to_bytes()

    for format in [
        CompressionFormat.Gzip, CompressionFormat.Zlib, CompressionFormat.Deflate
    ]:
        for level in [0, 9]:
            let encoded = try compress(data, format, CompressOptions(level: level))
            try expect_equal((try decompress(encoded, format)), data)
            try expect_equal((try decompress(encoded, format, data.length())), data)

            let limited: Bytes! = error(
                Error("compression: limit exceeded", kind: "EOVERFLOW")
            )
            try expect_equal(decompress(encoded, format, data.length() - 1), limited)

        let invalid: Bytes! = error(Error("compression: invalid input", kind: "EINVAL"))
        try expect_equal(compress(data, format, CompressOptions(level: -1)), invalid)
        try expect_equal(
            compress(data, format, CompressOptions(max_bytes: -1)), invalid
        )

        let zero: Bytes! = error(
            Error("compression: limit exceeded", kind: "EOVERFLOW")
        )
        try expect_equal(compress(data, format, CompressOptions(max_bytes: 0)), zero)

    let encoded = try compress(
        data, CompressionFormat.Gzip, CompressOptions(max_bytes: 1024)
    )
    let decoder = decompress
    try expect_equal((try decoder(encoded, CompressionFormat.Gzip)), data)

    let malformed: Bytes! = error(Error("compression: invalid data", kind: "EBADMSG"))
    try expect_equal(decompress(data, CompressionFormat.Gzip), malformed)

test "typed archives retain entry limits and validation":
    let entries = [ArchiveEntry("file.txt", "data".to_bytes(), false)]

    for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
        let encoded = try pack(entries, format)
        try expect_equal((try unpack(encoded, format)), entries)
        try expect_equal((try unpack(encoded, format, ArchiveOptions())), entries)

        let limited: List[ArchiveEntry]! = error(
            Error("archive: limit exceeded", kind: "EOVERFLOW")
        )
        try expect_equal(
            unpack(encoded, format, ArchiveOptions(max_entries: 0)), limited
        )

        let invalid: Bytes! = error(Error("archive: invalid input", kind: "EINVAL"))
        try expect_equal(
            pack([ArchiveEntry("../escape", "".to_bytes(), false)], format), invalid
        )
        try expect_equal(pack(entries, format, -1), invalid)
