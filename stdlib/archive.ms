import Bytes from "@std/bytes.ms"
import ReadStream from "@std/io.ms"

extern fn msrt_archive_pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Int?
) Result[Bytes, ArchiveError]

extern fn msrt_archive_unpack(
    data: Bytes,
    format: String,
    limits: ArchiveLimits?
) Result[List[ArchiveEntry], ArchiveError]

extern fn msrt_compress_compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Int?
) Result[Bytes, CompressionError]

extern fn msstd_archive_compress_stream(
    format: String,
    input: ReadStream,
    level: Int
) ReadStream

extern fn msstd_archive_decompress_stream(
    format: String,
    input: ReadStream,
    max_bytes: Int?
) ReadStream

extern fn msrt_compress_decompress(
    data: Bytes,
    format: String,
    max_bytes: Int?
) Result[Bytes, CompressionError]

# Errors returned when an archive cannot be read or written.
export type ArchiveError:
    # A format argument's entry paths, directory payloads or supplied output/unpack limits are invalid.
    case InvalidInput
    # Archive bytes, duplicate or file/directory-conflicting paths, extracted entry paths or encoded metadata are invalid.
    case InvalidData
    # Encoded bytes, entry count or unpacked per-entry/total bytes exceed a supplied budget.
    case LimitExceeded
    # The selected format or an encountered entry kind is unsupported, such as links or special files.
    case Unsupported
    # An explicit implementation-supplied archive diagnostic; native validation uses specific cases.
    case Failed(
        # Original diagnostic text, returned unchanged by message().
        message: String
    )

# One file or directory in an archive. Paths use forward slashes.
export type ArchiveEntry:
    # Relative forward-slash path; pack/unpack reject traversal, absolute paths and duplicate normalized names. Unpack returns directory paths without a trailing slash.
    path: String
    # File contents as immutable bytes; directory entries must carry empty bytes.
    data: Bytes
    # True for a directory entry rather than a regular file; links and special files are not supported.
    directory: Bool

# Optional limits applied while unpacking untrusted archive data.
export type ArchiveLimits:
    # Maximum unpacked entries, including directories; none adds no entry-count budget.
    max_entries: Int?
    # Maximum unpacked bytes for each entry; zero admits only empty data.
    max_entry_bytes: Int?
    # Cumulative unpacked file bytes across all entries; none adds no total-output budget.
    max_total_bytes: Int?

# Encodes entries as exactly `zip` or `tar` bytes (case-sensitive); others return Unsupported. `max_bytes` bounds output when supplied.
export fn pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Int?
) Result[Bytes, ArchiveError]:
    return msrt_archive_pack(entries, format, max_bytes)

# Decodes exactly `zip` or `tar` (case-sensitive); other formats return Unsupported.
# Applies each supplied entry and total-size limit.
export fn unpack(
    data: Bytes,
    format: String,
    limits: ArchiveLimits?
) Result[List[ArchiveEntry], ArchiveError]:
    return msrt_archive_unpack(data, format, limits)

impl Error for ArchiveError:
    # Returns original Failed text, or an archive-prefixed diagnostic for other cases.
    fn message() String:
        match self:
            InvalidInput: return "archive: invalid input"
            InvalidData: return "archive: invalid data"
            LimitExceeded: return "archive: limit exceeded"
            Unsupported: return "archive: operation not supported"
            Failed(message): return message.clone()

# Selects a supported archive format without a runtime string spelling check.
# Existing pack/unpack format: String calls remain available.
export type ArchiveFormat:
    # ZIP files and directories.
    case Zip
    # TAR files and directories.
    case Tar

fn archive_format_name(format: ArchiveFormat) String:
    match format:
        Zip: return "zip"
        Tar: return "tar"

impl ArchiveFormat:
    # Packs entries with the same optional output budget and path validation as pack.
    fn pack(entries: List[ArchiveEntry], max_bytes: Int?) Result[Bytes, ArchiveError]:
        return pack(entries, archive_format_name(self), max_bytes)

    # Unpacks in memory with the same entry/byte limits and domain errors as unpack.
    fn unpack(
        data: Bytes,
        limits: ArchiveLimits?
    ) Result[List[ArchiveEntry], ArchiveError]:
        return unpack(data, archive_format_name(self), limits)

# Errors returned when compressed data is unsupported, invalid, or exceeds a limit.
export type CompressionError:
    # Compression level is outside 0..9, or a supplied encoded/decoded byte budget is negative.
    case InvalidInput
    # Compressed framing, checksum, payload or trailing data is invalid for the chosen format.
    case InvalidData
    # Encoded or decompressed output exceeds the supplied byte budget.
    case LimitExceeded
    # A String selector is not exactly gzip, zlib or deflate; typed selectors avoid spelling errors.
    case Unsupported
    # An explicit implementation-supplied compression diagnostic; native codecs use specific cases.
    case Failed(
        # Original diagnostic text, returned unchanged by message().
        message: String
    )

# Compresses using exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive).
# Other formats return Unsupported; level defaults to 6 (balanced DEFLATE compression).
# Explicit levels must be 0..9 (0 stores data), else InvalidInput.
# `max_bytes` bounds the encoded output when supplied.
export fn compress(
    data: Bytes,
    format: String,
    level: Int = 6,
    max_bytes: Int?
) Result[Bytes, CompressionError]:
    return msrt_compress_compress(data, format, level, max_bytes)

# Decompresses exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive); others return Unsupported.
# Stops when the supplied output limit is reached.
export fn decompress(
    data: Bytes,
    format: String,
    max_bytes: Int?
) Result[Bytes, CompressionError]:
    return msrt_compress_decompress(data, format, max_bytes)

impl Error for CompressionError:
    # Returns original Failed text, or a compression-prefixed diagnostic for other cases.
    fn message() String:
        match self:
            InvalidInput: return "compression: invalid input"
            InvalidData: return "compression: invalid data"
            LimitExceeded: return "compression: limit exceeded"
            Unsupported: return "compression: operation not supported"
            Failed(message): return message.clone()

# Selects a supported compression format; Deflate is raw DEFLATE without a wrapper.
# Existing compress/decompress format: String calls remain available.
export type CompressionFormat:
    # DEFLATE data wrapped in GZIP headers and a checksum trailer.
    case Gzip
    # DEFLATE data with ZLIB header and Adler-32 checksum framing.
    case Zlib
    # Raw DEFLATE without framing.
    case Deflate

fn compression_format_name(format: CompressionFormat) String:
    match format:
        Gzip: return "gzip"
        Zlib: return "zlib"
        Deflate: return "deflate"

impl CompressionFormat:
    # Compresses with level 6 by default; explicit levels remain 0..9 (0 stores data).
    # Uses the same optional output budget/domain errors as compress.
    fn compress(
        data: Bytes,
        level: Int = 6,
        max_bytes: Int?
    ) Result[Bytes, CompressionError]:
        return compress(data, compression_format_name(self), level, max_bytes)

    # Decompresses with the same cumulative output limit and validation as decompress.
    fn decompress(data: Bytes, max_bytes: Int?) Result[Bytes, CompressionError]:
        return decompress(data, compression_format_name(self), max_bytes)

    # Returns a stream of this format's compressed bytes, reading `input` chunk by chunk.
    # Level defaults to 6 and must be 0..9, otherwise reads fail with InvalidInput.
    # Closing the result closes `input`.
    fn compress_stream(input: ReadStream, level: Int = 6) ReadStream:
        return msstd_archive_compress_stream(
            compression_format_name(self), input, level
        )

    # Returns a stream of decompressed bytes, reading `input` chunk by chunk.
    # Malformed data fails reads with InvalidData; `max_bytes` bounds total output and exceeding it fails with LimitExceeded.
    # Closing the result closes `input`.
    fn decompress_stream(input: ReadStream, max_bytes: Int?) ReadStream:
        return msstd_archive_decompress_stream(
            compression_format_name(self), input, max_bytes
        )
