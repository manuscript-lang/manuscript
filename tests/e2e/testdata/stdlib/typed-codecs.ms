import {expect_equal} from "@std/testing.ms"
import {HashAlgorithm, sha256, sha384, sha512, CryptoError} from "@std/crypto.ms"
import {CompressionFormat, compress, decompress, CompressionError} from "@std/compress.ms"
import {ArchiveFormat, pack, unpack, ArchiveEntry, ArchiveLimits, ArchiveError} from "@std/archive.ms"
import Bytes from "@std/bytes.ms"

fn digest(algorithm: HashAlgorithm, data: Bytes) Bytes:
    return algorithm.digest(data)

fn call_digest[T](operation: fn(data: Bytes) T, data: Bytes) T:
    return operation(data)

fn bounded_compression(
    operation: fn(
        data: Bytes,
        level: Int,
        max_bytes: Optional[Int]
    ) Result[Bytes, CompressionError],
    data: Bytes
) Result[Bytes, CompressionError]:
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
            (try algorithm.hmac(key, data)).length(),
            (algorithm.digest(data).length())
        )
    let hmac_operation = HashAlgorithm.Sha512.hmac
    try expect_equal(
        (try hmac_operation(key, data)),
        (try HashAlgorithm.Sha512.hmac(key, data))
    )

test "typed compression preserves bytes limits errors and optional arguments":
    let data = "typed codecs typed codecs".to_bytes()

    for format in [
        CompressionFormat.Gzip,
        CompressionFormat.Zlib,
        CompressionFormat.Deflate
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
            let limited: Result[Bytes, CompressionError] = error(
                CompressionError.LimitExceeded
            )
            try expect_equal(format.decompress(encoded, data.length() - 1), limited)

        let invalid: Result[Bytes, CompressionError] = error(
            CompressionError.InvalidInput
        )
        try expect_equal(format.compress(data, -1), invalid)
        try expect_equal(format.compress(data, 6, -1), invalid)
        let zero: Result[Bytes, CompressionError] = error(
            CompressionError.LimitExceeded
        )
        try expect_equal(format.compress(data, 6, 0), zero)

    let stored = CompressionFormat.Gzip.compress
    let encoded = try bounded_compression(stored, data)
    let decoder = CompressionFormat.Gzip.decompress
    try expect_equal((try decoder(encoded)), data)
    try expect_equal((try decompress(encoded, "gzip")), data)
    let malformed: Result[Bytes, CompressionError] = error(CompressionError.InvalidData)
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
        let limited: Result[List[ArchiveEntry], ArchiveError] = error(
            ArchiveError.LimitExceeded
        )
        try expect_equal(format.unpack(encoded, ArchiveLimits(0)), limited)
        let invalid: Result[Bytes, ArchiveError] = error(ArchiveError.InvalidInput)
        try expect_equal(
            format.pack([ArchiveEntry("../escape", "".to_bytes(), false)]),
            invalid
        )
        try expect_equal(format.pack(entries, -1), invalid)

    let stored = ArchiveFormat.Zip.pack
    let unpacker = ArchiveFormat.Zip.unpack
    try expect_equal(
        (stored(entries, none) | try | unpacker(ArchiveLimits()) | try),
        entries
    )
