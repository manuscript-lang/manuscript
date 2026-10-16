import Bytes from "@std/bytes.ms"

# A file-like byte stream that returns `none` at end of input.
export interface File:
    # Releases the file resource; retained aliases do not extend its open lifetime.
    fn close() -> Unit
    # Returns a byte chunk or none at EOF; max_bytes is a positive chunk size, not a total budget.
    # Omission/none uses the native 64 KiB chunk; source implementations define their own buffering.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

# Opens read-only file resources using the current host's default filesystem.
# Native open failures (including missing paths and permission denial) become IoError.Unavailable.
export interface Files:
    # Opens path for read-only access; native missing, denied, and other open failures become Unavailable.
    fn open(path: String) -> Result[File, IoError]

# Errors returned while reading, writing, or closing an I/O resource.
export type IoError:
    # The stream or shared native handle was closed before the operation completed.
    case Closed
    # An explicit chunk size, byte limit, or handle mode is invalid for this operation.
    case InvalidInput
    # The native service could not open or provide the requested stream.
    case Unavailable
    # Read bytes are invalid for the requested decoding, such as malformed UTF-8 text.
    case InvalidData
    # A supplied byte budget was exceeded; already consumed input may not be recoverable.
    case LimitExceeded
    # A native or adapter failure outside the more specific I/O cases.
    case Failed(
        # Original diagnostic text; message() returns it unchanged rather than redacting it.
        message: String
    )

# A readable byte stream. Each read returns a chunk or `none` at end of stream.
export interface ReadStream:
    # Releases this implementation's read resource; ownership of underlying handles is implementation-defined.
    fn close() -> Unit
    # Returns a chunk or none at EOF; a final nonempty chunk can precede EOF.
    # A supplied positive max_bytes requests a chunk size; native omission/none uses 64 KiB.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

# A writable byte stream. Successful write accepts all bytes; failure may leave an external prefix.
# Buffering/flush depends on the implementation: native stdout/stderr are unbuffered (flush is a no-op),
# while FileHandle.writer().flush synchronizes the file. Success does not acknowledge peer processing.
export interface WriteStream:
    # Releases this implementation's write resource; close does not imply a successful flush.
    fn close() -> Unit
    # Completes implementation-specific buffering or synchronization; native stdout/stderr use a no-op.
    # File-handle writers synchronize the file, and failures retain IoError identity.
    fn flush() -> Result[Unit, IoError]
    # Accepts the complete input on success; a source implementation may buffer until flush.
    fn write(data: Bytes) -> Result[Unit, IoError]

# Copies bytes until end of input or the supplied byte limit; returns bytes copied.
export fn copy(
    input: ReadStream,
    output: WriteStream,
    max_bytes: Optional[Int] = none
) -> Result[Int, IoError]:

# Reads a stream completely into memory. Supply a limit for untrusted streams.
export fn read_all(
    input: ReadStream,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, IoError]:

# Reads one line, omitting its line ending; returns `none` at end of stream.
export fn read_line(
    input: ReadStream,
    max_bytes: Optional[Int] = none
) -> Result[Optional[String], IoError]:

impl Error for IoError:
    # Returns original Failed text, or an I/O-prefixed diagnostic for the other cases.
    fn message() -> String:

# Returns the process standard-input stream.
export fn stdin() -> ReadStream:

# Returns the process standard-output stream.
export fn stdout() -> WriteStream:

# Returns the process standard-error stream.
export fn stderr() -> WriteStream:

# Returns file operations for the current host.
export fn files() -> Files:
# documentation documentation/standard-library/streams.md
# +++
# title = "Byte streams"
# weight = 11
# +++
#
# # Byte streams
#
# A stream reads or writes bytes over time. Its close operation releases the underlying resource. Native hosts and source fakes can both implement the contracts below.
#
# The host supplies synchronized `ReadStream`, `WriteStream`, and `File` views. All stream contract values are safe to share; closing a stream still closes it through every alias.
#
# The signatures are in the [`@std/io.ms` reference](reference/io.md).
#
# Read requires positive max_bytes or returns IoError.InvalidInput. Under the declared return type, `ok(value: bytes)` wraps 1 through max_bytes bytes in a present Optional; `ok(value: none)` is EOF. Empty chunks never represent EOF. The bound limits each read, not total file size. Write waits until all bytes are accepted or an error occurs; empty writes succeed without I/O. An error may follow a partial external write and supplies no rollback. Internal buffering is bounded with backpressure.
#
# Native wrappers serialize simultaneous reads/writes without holding a lifecycle lock during blocking I/O. Close marks admission closed, interrupts active I/O where supported, waits for admitted I/O to end, and releases the handle once. Later calls return IoError.Closed. Concurrent close callers wait for the same release/fault. A flag check followed by unsynchronized handle use is insufficient. Uncancellable I/O can delay release and requires host escalation; expected completion errors belong to read/write, and unexpected release failures are cleanup faults.
#
# Contract values declaring these exact close operations are eligible for `with` under [Closeable](../core-language/cleanup/closeable.md); cleanup does not require concurrent sharing. Source fakes implement the selected stream contract and explicitly construct contract views when substituting for standard host roots or acquisitions; no native File constructor or contract inheritance is needed.
# end-documentation
