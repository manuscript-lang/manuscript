import {compress, decompress, CompressionError} from "@std/compress.ms"
import {pack, unpack, ArchiveEntry, ArchiveLimits, ArchiveError} from "@std/archive.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "compression formats roundtrip and enforce expanded byte budgets":
    let input = "hello hello hello".to_bytes()
    for format in ["gzip", "zlib", "deflate"]:
        let packed = value(compress(data: input, format: format, level: 6))
        if value(decompress(data: packed, format: format, max_bytes: some(value: 17))) != input: return panic("compression roundtrip")
        let limited: Result[Bytes, CompressionError] = error(cause: CompressionError.LimitExceeded)
        if decompress(data: packed, format: format, max_bytes: some(value: 16)) != limited: return panic("expanded byte budget")
    let unsupported: Result[Bytes, CompressionError] = error(cause: CompressionError.Unsupported)
    if compress(data: input, format: "invalid", level: 6) != unsupported: return panic("unsupported format")
    let malformed: Result[Bytes, CompressionError] = error(cause: CompressionError.InvalidData)
    if decompress(data: input, format: "gzip") != malformed: return panic("invalid compressed data")

test "ZIP and TAR preserve entries and independently enforce archive limits":
    let entries = [ArchiveEntry(path: "a.txt", data: "hello".to_bytes(), directory: false), ArchiveEntry(path: "b.txt", data: "bye".to_bytes(), directory: false)]
    for format in ["zip", "tar"]:
        let packed = value(pack(entries: entries, format: format))
        if value(unpack(data: packed, format: format)) != entries: return panic("archive roundtrip")
        let limited: Result[List[ArchiveEntry], ArchiveError] = error(cause: ArchiveError.LimitExceeded)
        if unpack(data: packed, format: format, limits: some(value: ArchiveLimits(max_entries: some(value: 1)))) != limited: return panic("entry count")
        if unpack(data: packed, format: format, limits: some(value: ArchiveLimits(max_entry_bytes: some(value: 4)))) != limited: return panic("entry bytes")
        if unpack(data: packed, format: format, limits: some(value: ArchiveLimits(max_total_bytes: some(value: 7)))) != limited: return panic("total bytes")

test "archives reject traversal paths":
    let invalid: Result[Bytes, ArchiveError] = error(cause: ArchiveError.InvalidInput)
    for path in ["../escape", "/absolute"]:
        let entries = [ArchiveEntry(path: path, data: "".to_bytes(), directory: false)]
        if pack(entries: entries, format: "zip") != invalid: return panic("unsafe archive path")
