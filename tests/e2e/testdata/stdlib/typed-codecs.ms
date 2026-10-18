import {expect_equal, expect_ok} from "@std/testing.ms"
import {HashAlgorithm, sha256, sha384, sha512, hmac, CryptoError} from "@std/crypto.ms"
import {CompressionFormat, compress, decompress, CompressionError} from "@std/compress.ms"
import {ArchiveFormat, pack, unpack, ArchiveEntry, ArchiveLimits, ArchiveError} from "@std/archive.ms"
import Bytes from "@std/bytes.ms"

fn digest(algorithm: HashAlgorithm, data: Bytes) -> Bytes:
    return algorithm.digest(data)

fn call_digest[T](operation: fn(data: Bytes) -> T, data: Bytes) -> T:
    return operation(data)

fn bounded_compression(
    operation: fn(
        data: Bytes,
        level: Int,
        max_bytes: Optional[Int]
    ) -> Result[Bytes, CompressionError],
    data: Bytes
) -> Result[Bytes, CompressionError]:
    return operation(data, 6, 1024)

test "typed SHA selectors match their algorithms and retain bound operations":
    let data = "abc".to_bytes()
    digest(HashAlgorithm.Sha256, data) | try expect_equal(expected: sha256(data))
    digest(HashAlgorithm.Sha384, data) | try expect_equal(expected: sha384(data))
    digest(HashAlgorithm.Sha512, data) | try expect_equal(expected: sha512(data))
    let stored = HashAlgorithm.Sha384.digest
    stored(data) | try expect_equal(expected: sha384(data))
    call_digest(stored, data) | try expect_equal(expected: sha384(data))
    let key = "key".to_bytes()

    for algorithm in [HashAlgorithm.Sha256, HashAlgorithm.Sha384, HashAlgorithm.Sha512]:
        let name = match algorithm:
            Sha256: "sha256"
            Sha384: "sha384"
            Sha512: "sha512"

        algorithm.hmac(key, data) | try expect_ok | try expect_equal(
            expected: (hmac(key, data, name) | try expect_ok)
        )

    let hmac_operation = HashAlgorithm.Sha512.hmac
    hmac_operation(key, data) | try expect_ok | try expect_equal(
        expected: (hmac(key, data, "sha512") | try expect_ok)
    )
    let unsupported: Result[Bytes, CryptoError] = error(CryptoError.Unsupported)
    hmac(key, data, "SHA256") | try expect_equal(expected: unsupported)

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
            let encoded = (format.compress(data, level) | try expect_ok)
            encoded | try expect_equal(
                expected: (
                    compress(
                        data,
                        name,
                        level,
                        none
                    ) | try expect_ok
                )
            )
            format.decompress(encoded, none) | try expect_ok | try expect_equal(
                expected: data
            )
            try expect_equal(
                (
                    format.decompress(
                        encoded,
                        data.length()
                    ) | try expect_ok
                ),
                data
            )
            let limited: Result[Bytes, CompressionError] = error(
                CompressionError.LimitExceeded
            )
            format.decompress(encoded, data.length() - 1) | try expect_equal(
                expected: limited
            )

        let invalid: Result[Bytes, CompressionError] = error(
            CompressionError.InvalidInput
        )
        format.compress(data, -1) | try expect_equal(expected: invalid)
        format.compress(data, 6, -1) | try expect_equal(expected: invalid)
        let zero: Result[Bytes, CompressionError] = error(
            CompressionError.LimitExceeded
        )
        format.compress(data, 6, 0) | try expect_equal(expected: zero)

    let stored = CompressionFormat.Gzip.compress
    let encoded = (bounded_compression(stored, data) | try expect_ok)
    let decoder = CompressionFormat.Gzip.decompress
    decoder(encoded) | try expect_ok | try expect_equal(expected: data)
    decompress(encoded, "gzip") | try expect_ok | try expect_equal(expected: data)
    let malformed: Result[Bytes, CompressionError] = error(CompressionError.InvalidData)
    CompressionFormat.Gzip.decompress(data) | try expect_equal(expected: malformed)

test "typed archives retain entry limits validation and existing string calls":
    let entries = [ArchiveEntry("file.txt", "data".to_bytes(), false)]

    for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
        let name = match format:
            Zip: "zip"
            Tar: "tar"

        let encoded = (format.pack(entries) | try expect_ok)
        encoded | try expect_equal(expected: (pack(entries, name) | try expect_ok))
        format.unpack(encoded) | try expect_ok | try expect_equal(expected: entries)
        format.unpack(encoded, none) | try expect_ok | try expect_equal(
            expected: entries
        )
        unpack(encoded, name) | try expect_ok | try expect_equal(expected: entries)
        let limited: Result[List[ArchiveEntry], ArchiveError] = error(
            ArchiveError.LimitExceeded
        )
        format.unpack(encoded, ArchiveLimits(max_entries: 0)) | try expect_equal(
            expected: limited
        )
        let invalid: Result[Bytes, ArchiveError] = error(ArchiveError.InvalidInput)
        format.pack([ArchiveEntry("../escape", "".to_bytes(), false)]) | try expect_equal(
            expected: invalid
        )
        format.pack(entries, -1) | try expect_equal(expected: invalid)

    let stored = ArchiveFormat.Zip.pack
    let unpacker = ArchiveFormat.Zip.unpack
    try expect_equal(
        (
            unpacker(
                (stored(entries, none) | try expect_ok),
                ArchiveLimits()
            ) | try expect_ok
        ),
        entries
    )
