from "@std/sync.ms" import lock
from "@std/bytes.ms" import Bytes
from "@std/io.ms" import ReadStream, WriteStream, IoError
from "@std/shared.ms" import Shared, share
from "@std/core.ms" import Closeable

extern def msrt_archive_pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Optional[Int]
) -> Result[Bytes, ArchiveError]

extern def msrt_archive_unpack(
    data: Bytes,
    format: String,
    limits: Optional[ArchiveLimits]
) -> Result[List[ArchiveEntry], ArchiveError]

extern def msrt_compress_compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Optional[Int]
) -> Result[Bytes, CompressionError]

extern def msstd_archive_compress_stream(
    format: String,
    input: ReadStream,
    level: Int
) -> ReadStream

extern def msstd_archive_decompress_stream(
    format: String,
    input: ReadStream,
    max_bytes: Optional[Int]
) -> ReadStream

extern def msrt_compress_decompress(
    data: Bytes,
    format: String,
    max_bytes: Optional[Int]
) -> Result[Bytes, CompressionError]

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
    max_entries: Optional[Int] = none
    # Maximum unpacked bytes for each entry; zero admits only empty data.
    max_entry_bytes: Optional[Int] = none
    # Cumulative unpacked file bytes across all entries; none adds no total-output budget.
    max_total_bytes: Optional[Int] = none

# Encodes entries as exactly `zip` or `tar` bytes (case-sensitive); others return Unsupported. `max_bytes` bounds output when supplied.
export def pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, ArchiveError]:
    return msrt_archive_pack(entries, format, max_bytes)

# Decodes exactly `zip` or `tar` (case-sensitive); other formats return Unsupported.
# Applies each supplied entry and total-size limit.
export def unpack(
    data: Bytes,
    format: String,
    limits: Optional[ArchiveLimits] = none
) -> Result[List[ArchiveEntry], ArchiveError]:
    return msrt_archive_unpack(data, format, limits)

impl Error for ArchiveError:
    # Returns original Failed text, or an archive-prefixed diagnostic for other cases.
    def message() -> String:
        match self:
            case InvalidInput: return "archive: invalid input"
            case InvalidData: return "archive: invalid data"
            case LimitExceeded: return "archive: limit exceeded"
            case Unsupported: return "archive: operation not supported"
            case Failed(message): return message.clone()

# Selects a supported archive format without a runtime string spelling check.
# Existing pack/unpack format: String calls remain available.
export type ArchiveFormat:
    # ZIP files and directories.
    case Zip
    # TAR files and directories.
    case Tar

def archive_format_name(format: ArchiveFormat) -> String:
    match format:
        case Zip: return "zip"
        case Tar: return "tar"

impl ArchiveFormat:
    # Packs entries with the same optional output budget and path validation as pack.
    def pack(
        entries: List[ArchiveEntry],
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, ArchiveError]:
        return pack(entries, archive_format_name(self), max_bytes)

    # Unpacks in memory with the same entry/byte limits and domain errors as unpack.
    def unpack(
        data: Bytes,
        limits: Optional[ArchiveLimits] = none
    ) -> Result[List[ArchiveEntry], ArchiveError]:
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
export def compress(
    data: Bytes,
    format: String,
    level: Int = 6,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, CompressionError]:
    return msrt_compress_compress(data, format, level, max_bytes)

# Decompresses exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive); others return Unsupported.
# Stops when the supplied output limit is reached.
export def decompress(
    data: Bytes,
    format: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, CompressionError]:
    return msrt_compress_decompress(data, format, max_bytes)

impl Error for CompressionError:
    # Returns original Failed text, or a compression-prefixed diagnostic for other cases.
    def message() -> String:
        match self:
            case InvalidInput: return "compression: invalid input"
            case InvalidData: return "compression: invalid data"
            case LimitExceeded: return "compression: limit exceeded"
            case Unsupported: return "compression: operation not supported"
            case Failed(message): return message.clone()

# Selects a supported compression format; Deflate is raw DEFLATE without a wrapper.
# Existing compress/decompress format: String calls remain available.
export type CompressionFormat:
    # DEFLATE data wrapped in GZIP headers and a checksum trailer.
    case Gzip
    # DEFLATE data with ZLIB header and Adler-32 checksum framing.
    case Zlib
    # Raw DEFLATE without framing.
    case Deflate

def compression_format_name(format: CompressionFormat) -> String:
    match format:
        case Gzip: return "gzip"
        case Zlib: return "zlib"
        case Deflate: return "deflate"

impl CompressionFormat:
    # Compresses with level 6 by default; explicit levels remain 0..9 (0 stores data).
    # Uses the same optional output budget/domain errors as compress.
    def compress(
        data: Bytes,
        level: Int = 6,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, CompressionError]:
        return compress(data, compression_format_name(self), level, max_bytes)

    # Decompresses with the same cumulative output limit and validation as decompress.
    def decompress(
        data: Bytes,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, CompressionError]:
        return decompress(data, compression_format_name(self), max_bytes)

    # Returns a stream of this format's compressed bytes, reading `input` chunk by chunk.
    # Level defaults to 6 and must be 0..9, otherwise reads fail with InvalidInput.
    # Closing the result closes `input`.
    def compress_stream(input: ReadStream, level: Int = 6) -> ReadStream:
        return msstd_archive_compress_stream(
            compression_format_name(self), input, level
        )

    # Returns a stream of decompressed bytes, reading `input` chunk by chunk.
    # Malformed data fails reads with InvalidData; `max_bytes` bounds total output and exceeding it fails with LimitExceeded.
    # Closing the result closes `input`.
    def decompress_stream(
        input: ReadStream,
        max_bytes: Optional[Int] = none
    ) -> ReadStream:
        return msstd_archive_decompress_stream(
            compression_format_name(self), input, max_bytes
        )

# Internal owned native incremental encoder; construct through compress_writer.
export extern type NativeCompressionEncoder

extern def msrt_compress_encoder_new(
    format: String,
    level: Int
) -> Result[NativeCompressionEncoder, CompressionError]

extern def msrt_compress_encoder_feed(
    encoder: NativeCompressionEncoder,
    data: Bytes
) -> Unit

extern def msrt_compress_encoder_flush(encoder: NativeCompressionEncoder) -> Unit

extern def msrt_compress_encoder_finish(encoder: NativeCompressionEncoder) -> Unit

extern def msrt_compress_encoder_has_output(encoder: NativeCompressionEncoder) -> Bool

extern def msrt_compress_encoder_take(
    encoder: NativeCompressionEncoder,
    max: Int
) -> Bytes

# Internal shared state of CompressionWriter; callers should use compress_writer.
export type CompressionWriteState:
    # Owned codec handle, shared only by aliases of one writer.
    encoder: NativeCompressionEncoder
    # Remaining uncompressed input-byte budget.
    remaining_input: Int
    # Remaining encoded output-byte budget.
    remaining_output: Int
    # Whether an operation owns the destination; reentrant operations are rejected.
    busy: Bool = False
    # Whether finish, close or failure invalidated all aliases.
    closed: Bool = False

type CompressionHeld[T]:
    value: T

impl Closeable for CompressionHeld[T]:
    var def close() -> Unit: ()

# Incremental compression with shared lifetime across writer aliases.
# Feed chunks are at most 64 KiB and output drains before more input is accepted.
# finish is required on success; close abandons the encoder without finalizing or closing its destination.
export type CompressionWriter:
    # Internal shared codec, byte budgets and operation/lifetime flags.
    state: Shared[CompressionWriteState]
    # Internal destination, exclusively borrowed during each output operation.
    output: Shared[WriteStream]

impl CompressionWriter:
    # Internal entry check. Reentrant, cancelled, failed or finished writers report Closed.
    def begin() -> Result[Unit, IoError]:
        if self.state.get().closed or self.state.get().busy: return error(
            IoError.Closed
        )

        with var state_guard = lock(self.state):
            state_guard.value.busy = True
        return ok(())

    # Internal completion; a failed operation poisons every alias.
    def end(
        result: Result[Unit, IoError],
        finish: Bool = False
    ) -> Result[Unit, IoError]:
        with var state_guard = lock(self.state):
            state_guard.value.busy = False
            state_guard.value.closed = (
                state_guard.value.closed
                or finish
                or result.is_error()
            )

        return result

    # Internal budget debit; all owned state returns before downstream suspension.
    def debit_output(size: Int) -> Result[Unit, IoError]:
        with var state_guard = lock(self.state):
            if size > state_guard.value.remaining_output:
                state_guard.value.closed = True
                return error(IoError.LimitExceeded)

            state_guard.value.remaining_output -= size

        return ok(())

    # Internal encoded-output pump; no codec borrow spans downstream suspension.
    def drain() -> Result[Unit, IoError]:
        while msrt_compress_encoder_has_output(self.state.get().encoder):
            if self.state.get().closed: return error(IoError.Closed)

            with let bytes = CompressionHeld(
                msrt_compress_encoder_take(
                    self.state.get().encoder, 65536
                )
            ):
                try self.debit_output(bytes.value.length())
                try self.output.get().write_bytes(bytes.value)

        return ok(())

    # Emits the format trailer exactly once after successful production, then invalidates aliases.
    # Failure or cancellation never triggers implicit finalization during cleanup.
    def finish() -> Result[Unit, IoError]:
        try self.begin()
        msrt_compress_encoder_finish(self.state.get().encoder)
        return self.end(self.drain(), True)

    # Internal input budget debit, completed before any downstream write.
    def debit_input(size: Int) -> Result[Unit, IoError]:
        with var state_guard = lock(self.state):
            if size > state_guard.value.remaining_input:
                state_guard.value.closed = True
                return error(IoError.LimitExceeded)

            state_guard.value.remaining_input -= size

        return ok(())

    # Internal bounded feed, returning an error before accepting bytes over the input limit.
    def feed(data: Bytes) -> Result[Unit, IoError]:
        try self.debit_input(data.length())

        var offset = 0

        while offset < data.length():
            let size = 65536 if data.length() - offset > 65536 else data.length() - offset

            msrt_compress_encoder_feed(
                self.state.get().encoder, data.slice(offset, offset + size).get()
            )
            try self.drain()
            offset += size

        return ok(())

impl CompressionWriter:
    # Returns a WriteStream alias sharing this encoder and its lifetime.
    def writer() -> WriteStream: return CompressionOutput(self.clone())

    # Performs a sync flush, drains encoded bytes, and flushes the destination without finishing.
    var def flush() -> Result[Unit, IoError]:
        try self.begin()
        msrt_compress_encoder_flush(self.state.get().encoder)

        let drained = self.drain()
        if drained.is_error(): return self.end(drained)

        return self.end(self.output.get().flush())

    # Compresses UTF-8 text while enforcing cumulative encoded and unencoded bounds.
    var def write(data: String) -> Result[Unit, IoError]:
        with let bytes = CompressionHeld(data.to_bytes()):
            return self.write_bytes(bytes.value)

    # Compresses bytes incrementally; a destination error poisons every writer alias.
    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        try self.begin()
        return self.end(self.feed(data))

# Creates an incremental compression writer. Explicit budgets are nonnegative; none is unlimited.
# The destination remains caller-owned. Call finish on success and close/leave scope on failure.
export def compress_writer(
    output: WriteStream,
    format: CompressionFormat = CompressionFormat.Gzip,
    level: Int = 6,
    max_input_bytes: Optional[Int] = none,
    max_output_bytes: Optional[Int] = none
) -> Result[CompressionWriter, CompressionError]:
    let input_limit = max_input_bytes.get(9223372036854775807)
    let output_limit = max_output_bytes.get(9223372036854775807)
    if input_limit < 0 or output_limit < 0: return error(CompressionError.InvalidInput)

    let encoder = try msrt_compress_encoder_new(compression_format_name(format), level)
    return ok(
        CompressionWriter(
            share(
                CompressionWriteState(
                    encoder, input_limit, output_limit
                )
            ),
            share(output)
        )
    )

impl Closeable for CompressionWriter:
    # Abandons the codec without finalization when a scope exits, including cancellation.
    var def close() -> Unit:
        with var state_guard = lock(self.state):
            state_guard.value.closed = True

type CompressionOutput:
    owner: CompressionWriter

impl WriteStream for CompressionOutput:
    var def close() -> Unit: self.owner.close()

    var def flush() -> Result[Unit, IoError]: return self.owner.flush()

    var def write(data: String) -> Result[Unit, IoError]: return self.owner.write(data)

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]: return (
        self
        .owner
        .write_bytes(data)
    )
