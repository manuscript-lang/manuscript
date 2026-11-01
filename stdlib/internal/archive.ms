import ReadStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import (
    ArchiveEntry,
    ArchiveError,
    ArchiveLimits,
    CompressionError
) from "@std/io/archive.ms"

export extern fn msstd_archive_compress_stream(
    format: String,
    input: ReadStream,
    level: Int
) ReadStream

export extern fn msstd_archive_decompress_stream(
    format: String,
    input: ReadStream,
    max_bytes: Int?
) ReadStream

export extern fn msstd_archive_pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Int?
) Bytes!ArchiveError

export extern fn msstd_archive_unpack(
    data: Bytes,
    format: String,
    limits: ArchiveLimits?
) List[ArchiveEntry]!ArchiveError

export extern fn msstd_compress_compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Int?
) Bytes!CompressionError

export extern fn msstd_compress_decompress(
    data: Bytes,
    format: String,
    max_bytes: Int?
) Bytes!CompressionError
