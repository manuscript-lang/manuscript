+++
title = "io"
+++

# @std/io.ms

Import each required symbol with `import Name from "@std/io.ms"`.

## File {data-api-kind="Interface"}

A file-like byte stream that returns `none` at end of input.

```manuscript
interface File:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], IoError]
```

### File.close

Releases the file resource; retained aliases do not extend its open lifetime.

```manuscript
fn close() -> Unit
```

### File.read

Returns a byte chunk or none at EOF; max_bytes is a positive chunk size, not a total budget.
Omission/none uses the native 64 KiB chunk; source implementations define their own buffering.

```manuscript
fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], IoError]
```

## Files {data-api-kind="Interface"}

Opens read-only file resources using the current host's default filesystem.
Native open failures (including missing paths and permission denial) become IoError.Unavailable.

```manuscript
interface Files:
    fn open(path: String) -> Result[File, IoError]
```

### Files.open

Opens path for read-only access; native missing, denied, and other open failures become Unavailable.

```manuscript
fn open(path: String) -> Result[File, IoError]
```

## IoError {data-api-kind="Alternative"}

Errors returned while reading, writing, or closing an I/O resource.

```manuscript
type IoError:
    case Closed
    case InvalidInput
    case Unavailable
    case InvalidData
    case LimitExceeded
    case Failed(message: String)
```

```manuscript
impl Error for IoError:
    fn message() -> String:
```

### IoError.Closed

The stream or shared native handle was closed before the operation completed.

```manuscript
case Closed
```

### IoError.Failed

A native or adapter failure outside the more specific I/O cases.

```manuscript
case Failed(message: String)
```

### IoError.InvalidData

Read bytes are invalid for the requested decoding, such as malformed UTF-8 text.

```manuscript
case InvalidData
```

### IoError.InvalidInput

An explicit chunk size, byte limit, or handle mode is invalid for this operation.

```manuscript
case InvalidInput
```

### IoError.LimitExceeded

A supplied byte budget was exceeded; already consumed input may not be recoverable.

```manuscript
case LimitExceeded
```

### IoError.Unavailable

The native service could not open or provide the requested stream.

```manuscript
case Unavailable
```

### IoError.Failed.message

Original diagnostic text; message() returns it unchanged rather than redacting it.

```manuscript
message: String
```

### IoError.Error.message

Returns original Failed text, or an I/O-prefixed diagnostic for the other cases.

```manuscript
fn message() -> String:
```

## ReadStream {data-api-kind="Interface"}

A readable byte stream. Each read returns a chunk or `none` at end of stream.

```manuscript
interface ReadStream:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], IoError]
```

### ReadStream.close

Releases this implementation's read resource; ownership of underlying handles is implementation-defined.

```manuscript
fn close() -> Unit
```

### ReadStream.read

Returns a chunk or none at EOF; a final nonempty chunk can precede EOF.
A supplied positive max_bytes requests a chunk size; native omission/none uses 64 KiB.

```manuscript
fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], IoError]
```

## WriteStream {data-api-kind="Interface"}

A writable byte stream. Successful write accepts all bytes; failure may leave an external prefix.
Buffering/flush depends on the implementation: native stdout/stderr are unbuffered (flush is a no-op),
while FileHandle.writer().flush synchronizes the file. Success does not acknowledge peer processing.

```manuscript
interface WriteStream:
    fn close() -> Unit
    fn flush() -> Result[Unit, IoError]
    fn write(data: Bytes) -> Result[Unit, IoError]
```

### WriteStream.close

Releases this implementation's write resource; close does not imply a successful flush.

```manuscript
fn close() -> Unit
```

### WriteStream.flush

Completes implementation-specific buffering or synchronization; native stdout/stderr use a no-op.
File-handle writers synchronize the file, and failures retain IoError identity.

```manuscript
fn flush() -> Result[Unit, IoError]
```

### WriteStream.write

Accepts the complete input on success; a source implementation may buffer until flush.

```manuscript
fn write(data: Bytes) -> Result[Unit, IoError]
```

## copy {data-api-kind="Function"}

Copies bytes until end of input or the supplied byte limit; returns bytes copied.

```manuscript
fn copy(input: ReadStream, output: WriteStream, max_bytes: Optional[Int64] = none) -> Result[Int64, IoError]:
```

## files {data-api-kind="Function"}

Returns file operations for the current host.

```manuscript
fn files() -> Files:
```

## read_all {data-api-kind="Function"}

Reads a stream completely into memory. Supply a limit for untrusted streams.

```manuscript
fn read_all(input: ReadStream, max_bytes: Optional[Int64] = none) -> Result[Bytes, IoError]:
```

## read_line {data-api-kind="Function"}

Reads one line, omitting its line ending; returns `none` at end of stream.

```manuscript
fn read_line(input: ReadStream, max_bytes: Optional[Int64] = none) -> Result[Optional[String], IoError]:
```

## stderr {data-api-kind="Function"}

Returns the process standard-error stream.

```manuscript
fn stderr() -> WriteStream:
```

## stdin {data-api-kind="Function"}

Returns the process standard-input stream.

```manuscript
fn stdin() -> ReadStream:
```

## stdout {data-api-kind="Function"}

Returns the process standard-output stream.

```manuscript
fn stdout() -> WriteStream:
```

