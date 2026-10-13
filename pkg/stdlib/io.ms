# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# A file-like byte stream that returns `none` at end of input.
export interface File:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

# Opens file resources using the current host's default filesystem.
export interface Files:
    fn open(path: String) -> Result[File, IoError]

# Errors returned while reading, writing, or closing an I/O resource.
export type IoError:
    case Closed
    case InvalidInput
    case Unavailable
    case InvalidData
    case LimitExceeded
    case Failed(message: String)

# A readable byte stream. Each read returns a chunk or `none` at end of stream.
export interface ReadStream:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

# A writable byte stream. Flush before relying on buffered data being delivered.
export interface WriteStream:
    fn close() -> Unit
    fn flush() -> Result[Unit, IoError]
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
    fn message() -> String:

# Returns the process standard-input stream.
export fn stdin() -> ReadStream:

# Returns the process standard-output stream.
export fn stdout() -> WriteStream:

# Returns the process standard-error stream.
export fn stderr() -> WriteStream:

# Returns file operations for the current host.
export fn files() -> Files:
