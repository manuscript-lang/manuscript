import {
    HashAlgorithm,
    sha256,
    sha384,
    sha512,
    hmac,
    CryptoError
} from "@std/crypto.ms"
import {CompressionFormat, compress, decompress, CompressionError} from "@std/compress.ms"
import {
    ArchiveFormat,
    pack,
    unpack,
    ArchiveEntry,
    ArchiveLimits,
    ArchiveError
} from "@std/archive.ms"
import {List, Map} from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

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
    if digest(HashAlgorithm.Sha256, data) != sha256(data): return panic(
        "SHA-256 selector"
    )
    if digest(HashAlgorithm.Sha384, data) != sha384(data): return panic(
        "SHA-384 selector"
    )
    if digest(HashAlgorithm.Sha512, data) != sha512(data): return panic(
        "SHA-512 selector"
    )

    let stored = HashAlgorithm.Sha384.digest
    if stored(data) != sha384(data): return panic("stored digest")

    if call_digest(stored, data) != sha384(data): return panic("generic stored digest")

    let key = "key".to_bytes()

    for algorithm in [HashAlgorithm.Sha256, HashAlgorithm.Sha384, HashAlgorithm.Sha512]:
        let name = match algorithm:
            Sha256: "sha256"
            Sha384: "sha384"
            Sha512: "sha512"

        if value(algorithm.hmac(key, data)) != value(hmac(key, data, name)): return panic(
            "typed HMAC"
        )

    let hmac_operation = HashAlgorithm.Sha512.hmac
    if value(hmac_operation(key, data)) != value(hmac(key, data, "sha512")): return panic(
        "stored HMAC"
    )

    let unsupported: Result[Bytes, CryptoError] = error(CryptoError.Unsupported)
    if hmac(key, data, "SHA256") != unsupported: return panic("legacy HMAC rejection")

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
            let encoded = value(format.compress(data, level))
            if encoded != value(compress(data, name, level, none)): return panic(
                "typed encoded bytes"
            )
            if value(format.decompress(encoded, none)) != data: return panic(
                "typed decompression"
            )
            if value(format.decompress(encoded, data.length())) != data: return panic(
                "typed exact budget"
            )

            let limited: Result[Bytes, CompressionError] = error(
                CompressionError.LimitExceeded
            )
            if format.decompress(encoded, data.length() - 1) != limited: return panic(
                "typed byte limit"
            )

        let invalid: Result[Bytes, CompressionError] = error(
            CompressionError.InvalidInput
        )
        if format.compress(data, -1) != invalid: return panic("typed level validation")
        if format.compress(data, 6, -1) != invalid: return panic("typed output budget")

        let zero: Result[Bytes, CompressionError] = error(
            CompressionError.LimitExceeded
        )
        if format.compress(data, 6, 0) != zero: return panic("typed zero output budget")

    let stored = CompressionFormat.Gzip.compress
    let encoded = value(bounded_compression(stored, data))
    let decoder = CompressionFormat.Gzip.decompress
    if value(decoder(encoded)) != data: return panic("stored decoder default")
    if value(decompress(encoded, "gzip")) != data: return panic("legacy decompression")

    let malformed: Result[Bytes, CompressionError] = error(CompressionError.InvalidData)
    if CompressionFormat.Gzip.decompress(data) != malformed: return panic(
        "typed malformed error"
    )

test "typed archives retain entry limits validation and existing string calls":
    let entries = [ArchiveEntry("file.txt", "data".to_bytes(), false)]

    for format in [ArchiveFormat.Zip, ArchiveFormat.Tar]:
        let name = match format:
            Zip: "zip"
            Tar: "tar"

        let encoded = value(format.pack(entries))
        if encoded != value(pack(entries, name)): return panic("typed archive bytes")
        if value(format.unpack(encoded)) != entries: return panic(
            "typed archive roundtrip"
        )
        if value(format.unpack(encoded, none)) != entries: return panic(
            "typed archive none"
        )
        if value(unpack(encoded, name)) != entries: return panic("legacy archive")

        let limited: Result[List[ArchiveEntry], ArchiveError] = error(
            ArchiveError.LimitExceeded
        )
        if format.unpack(encoded, ArchiveLimits(max_entries: 0)) != limited: return panic(
            "typed entry limit"
        )

        let invalid: Result[Bytes, ArchiveError] = error(ArchiveError.InvalidInput)
        if format.pack([ArchiveEntry("../escape", "".to_bytes(), false)]) != invalid: return panic(
            "typed path validation"
        )
        if format.pack(entries, -1) != invalid: return panic("typed negative budget")

    let stored = ArchiveFormat.Zip.pack
    let unpacker = ArchiveFormat.Zip.unpack
    if value(unpacker(value(stored(entries, none)), ArchiveLimits())) != entries: return panic(
        "stored archive operations"
    )
