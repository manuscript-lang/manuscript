import Bytes, BytesBuilder, join from "@std/bytes.ms"
import ReadStream, Transform, through from "@std/io/stream.ms"
import (
    msstd_compress_encoder_new,
    msstd_compress_encoder_push,
    msstd_compress_encoder_end,
    msstd_compress_decoder_new,
    msstd_compress_decoder_push,
    msstd_compress_decoder_end,
    msstd_archive_pack,
    msstd_archive_unpack,
    msstd_compress_compress,
    msstd_compress_decompress
) from "@std/internal/archive.ms"

// One file or directory in an archive. Paths use forward slashes.
export type ArchiveEntry:
    // Relative forward-slash path; pack/unpack reject traversal, absolute paths and duplicate normalized names. Tar unpack also skips a bare `./` entry and strips a leading `./` from member names (as in `tar -cf x.tar .`); pack stays strict. Unpack returns directory paths without a trailing slash.
    path: String
    // File contents as immutable bytes; directory entries must carry empty bytes.
    data: Bytes
    // True for a directory entry rather than a regular file; links and special files are not supported.
    directory: Bool

// Optional limits applied while unpacking untrusted archive data.
export type ArchiveLimits:
    // Maximum unpacked entries, including directories; none adds no entry-count budget.
    max_entries: Int?
    // Maximum unpacked bytes for each entry; zero admits only empty data.
    max_entry_bytes: Int?
    // Cumulative unpacked file bytes across all entries; none adds no total-output budget.
    max_total_bytes: Int?

// Encodes entries as exactly `zip` or `tar` bytes (case-sensitive); others return Unsupported. `max_bytes` bounds output when supplied.
export fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Int?) Bytes!:
    return msstd_archive_pack(entries, format, max_bytes)

// Decodes exactly `zip` or `tar` (case-sensitive); other formats return Unsupported.
// Applies each supplied entry and total-size limit.
export fn unpack(
    data: Bytes,
    format: String,
    limits: ArchiveLimits?
) List[ArchiveEntry]!:
    return msstd_archive_unpack(data, format, limits)

// Selects a supported archive format without a runtime string spelling check.
// Existing pack/unpack format: String calls remain available.
export type ArchiveFormat:
    case Zip  // ZIP files and directories.
    case Tar  // TAR files and directories.

fn archive_format_name(format: ArchiveFormat) String:
    match format:
        Zip: return "zip"
        Tar: return "tar"

impl ArchiveFormat:
    // Packs entries with the same optional output budget and path validation as pack.
    fn pack(entries: List[ArchiveEntry], max_bytes: Int?) Bytes!:
        return pack(entries, archive_format_name(self), max_bytes)

    // Unpacks in memory with the same entry/byte limits and domain errors as unpack.
    fn unpack(data: Bytes, limits: ArchiveLimits?) List[ArchiveEntry]!:
        return unpack(data, archive_format_name(self), limits)

/*
Compresses using exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive).
Other formats return Unsupported; level defaults to 6 (balanced DEFLATE compression).
Explicit levels must be 0..9 (0 stores data), else InvalidInput.
`max_bytes` bounds the encoded output when supplied.
*/
export fn compress(data: Bytes, format: String, level: Int = 6, max_bytes: Int?) Bytes!:
    return msstd_compress_compress(data, format, level, max_bytes)

// Decompresses exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive); others return Unsupported.
// Stops when the supplied output limit is reached.
export fn decompress(data: Bytes, format: String, max_bytes: Int?) Bytes!:
    return msstd_compress_decompress(data, format, max_bytes)

// Selects a supported compression format; Deflate is raw DEFLATE without a wrapper.
// Existing compress/decompress format: String calls remain available.
export type CompressionFormat:
    case Gzip  // DEFLATE data wrapped in GZIP headers and a checksum trailer.
    case Zlib  // DEFLATE data with ZLIB header and Adler-32 checksum framing.
    case Deflate  // Raw DEFLATE without framing.

fn compression_format_name(format: CompressionFormat) String:
    match format:
        Gzip: return "gzip"
        Zlib: return "zlib"
        Deflate: return "deflate"

impl CompressionFormat:
    // Compresses with level 6 by default; explicit levels remain 0..9 (0 stores data).
    // Uses the same optional output budget/domain errors as compress.
    fn compress(data: Bytes, level: Int = 6, max_bytes: Int?) Bytes!:
        return compress(data, compression_format_name(self), level, max_bytes)

    // Decompresses with the same cumulative output limit and validation as decompress.
    fn decompress(data: Bytes, max_bytes: Int?) Bytes!:
        return decompress(data, compression_format_name(self), max_bytes)

// A codec held by a stream step; `failure` is a construction error returned by every read.
export extern type NativeEncoder

export extern type NativeDecoder

type Compressing:
    encoder: NativeEncoder?
    failure: Error?

impl Transform[Bytes, Bytes] for Compressing:
    var fn feed(value: Bytes) List[Bytes]!:
        if let failure = self.failure: return error(failure.clone())

        var out: List[Bytes] = []

        if let encoder = self.encoder:
            let packed = msstd_compress_encoder_push(encoder, value)
            if not packed.is_empty(): out.append(packed)

        return ok(out)

    var fn finish() List[Bytes]!:
        if let failure = self.failure: return error(failure.clone())

        var out: List[Bytes] = []
        if let encoder = self.encoder:
            out.append(msstd_compress_encoder_end(encoder))
        self.encoder = none
        return ok(out)

// Compresses a byte stream into `format`, chunk by chunk, holding only the codec's window. `level` defaults to 6
// and must be 0..9, otherwise reads fail with `InvalidInput`. Closing the result closes `input`.
export fn compressed(
    input: ReadStream[Bytes],
    format: CompressionFormat,
    level: Int = 6
) ReadStream[Bytes]:
    let made = msstd_compress_encoder_new(compression_format_name(format), level)
    var step = Compressing(encoder: none, failure: none)

    if made.is_error():
        step.failure = made.err()
    else:
        step.encoder = made.get()

    return through[Bytes, Bytes](input, step)

type Decompressing:
    decoder: NativeDecoder?
    failure: Error?

impl Transform[Bytes, Bytes] for Decompressing:
    var fn feed(value: Bytes) List[Bytes]!:
        if let failure = self.failure: return error(failure.clone())

        var out: List[Bytes] = []

        if let decoder = self.decoder:
            let plain = try msstd_compress_decoder_push(decoder, value)
            if not plain.is_empty(): out.append(plain)

        return ok(out)

    var fn finish() List[Bytes]!:
        if let failure = self.failure: return error(failure.clone())

        var out: List[Bytes] = []

        if let decoder = self.decoder:
            let plain = try msstd_compress_decoder_end(decoder)
            if not plain.is_empty(): out.append(plain)

        self.decoder = none
        return ok(out)

// Decompresses a byte stream from `format`, chunk by chunk. Malformed or truncated data fails the read with
// `InvalidData`; `max_bytes` bounds the total output and exceeding it fails with `LimitExceeded`. Closing the
// result closes `input`.
export fn decompressed(
    input: ReadStream[Bytes],
    format: CompressionFormat,
    max_bytes: Int?
) ReadStream[Bytes]:
    let made = msstd_compress_decoder_new(compression_format_name(format), max_bytes)
    var step = Decompressing(decoder: none, failure: none)

    if made.is_error():
        step.failure = made.err()
    else:
        step.decoder = made.get()

    return through[Bytes, Bytes](input, step)

// Reads the octal (or base-256) size field of a tar header block.
fn tar_size(block: Bytes) Int:
    let first = block.get(124, 0).to_int()
    var size = 0

    if first >= 128:
        size = first - 128
        for i in 125..136:
            size = size * 256 + block.get(i, 0).to_int()
        return size

    for i in 124..136:
        let digit = block.get(i, 0).to_int()
        if digit < 48 or digit > 55: continue

        size = size * 8 + (digit - 48)

    return size

fn tar_is_zero(block: Bytes) Bool:
    for byte in block.values():
        if byte != 0: return false
    return true

// Frames a tar byte stream into members (extension headers, the header and its data) and unpacks each one with
// `unpack`, so one entry at a time is in memory.
type TarEntries:
    limits: ArchiveLimits
    buffer: Bytes
    count: Int
    total: Int
    done: Bool
    end: Bytes

impl TarEntries:
    // Bytes of the member at the start of the buffer, or 0 while its end has not arrived.
    fn member_length() Int!:
        var at = 0

        while true:
            if self.buffer.length() < at + 512: return ok(0)

            let block = try self.buffer.slice(at, at + 512)
            let flag = block.get(156, 0).to_int()
            let size = tar_size(block)
            var padded = (size + 511) / 512 * 512

            // 'x', 'g', 'L' and 'K' carry data for the header that follows them.
            let extension = flag == 120 or flag == 103 or flag == 76 or flag == 75
            at += 512
            if (
                flag == 53
                or flag == 49
                or flag == 50
                or flag == 51
                or flag == 52
                or flag == 54
                or flag == 55
            ):
                padded = 0
            at += padded
            if self.buffer.length() < at: return ok(0)
            if not extension: return ok(at)

        return ok(0)

impl Transform[Bytes, ArchiveEntry] for TarEntries:
    var fn feed(value: Bytes) List[ArchiveEntry]!:
        var out: List[ArchiveEntry] = []
        if self.done: return ok(out)

        self.buffer = self.buffer.concat(value)

        while true:
            if (
                self.buffer.length() >= 512
                and tar_is_zero(try self.buffer.slice(0, 512))
            ):
                self.done = true
                self.buffer = join([])
                break

            let length = try self.member_length()
            if length == 0: break

            let member = try self.buffer.slice(0, length)
            self.buffer = try self.buffer.slice(length, self.buffer.length())

            let end = member.concat(self.end)

            for entry in try unpack(end, "tar", self.limits):
                self.count += 1
                self.total += entry.data.length()
                out.append(entry)

            if let most = self.limits.max_entries:
                if self.count > most: return error(
                    Error(
                        "archive: limit exceeded", kind: LimitExceeded
                    )
                )
            if let most = self.limits.max_total_bytes:
                if self.total > most: return error(
                    Error(
                        "archive: limit exceeded", kind: LimitExceeded
                    )
                )

        return ok(out)

    var fn finish() List[ArchiveEntry]!:
        if self.done or self.buffer.is_empty(): return ok(List[ArchiveEntry]())

        return error(Error("archive: truncated tar", kind: InvalidData))

// Reads the entries of a tar byte stream one at a time, for archives too big to hold in memory. Each entry is
// validated as `unpack` does; `max_entry_bytes` bounds one entry and `max_entries` and `max_total_bytes` the
// whole archive, failing the read with `LimitExceeded`. A truncated archive fails with `InvalidData`. Closing
// the result closes `input`.
export fn tar_entries(
    input: ReadStream[Bytes],
    limits: ArchiveLimits = ArchiveLimits()
) ReadStream[ArchiveEntry]:
    var zeros = BytesBuilder()
    for index in 0..1024:
        zeros.append(0)
    return through[Bytes, ArchiveEntry](
        input,
        TarEntries(
            limits: limits, buffer: join([]), count: 0, total: 0, done: false,
            end: zeros.build()
        )
    )
