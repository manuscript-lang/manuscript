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
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

## Files {data-api-kind="Interface"}

Opens file resources using the current host's default filesystem.

```manuscript
interface Files:
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

## ReadStream {data-api-kind="Interface"}

A readable byte stream. Each read returns a chunk or `none` at end of stream.

```manuscript
interface ReadStream:
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

## WriteStream {data-api-kind="Interface"}

A writable byte stream. Flush before relying on buffered data being delivered.

```manuscript
interface WriteStream:
    fn close() -> Unit
    fn flush() -> Result[Unit, IoError]
    fn write(data: Bytes) -> Result[Unit, IoError]
```

## copy {data-api-kind="Function"}

Copies bytes until end of input or the supplied byte limit; returns bytes copied.

```manuscript
fn copy(input: ReadStream, output: WriteStream, max_bytes: Optional[Int] = none) -> Result[Int, IoError]:
```

## files {data-api-kind="Function"}

Returns file operations for the current host.

```manuscript
fn files() -> Files:
```

## read_all {data-api-kind="Function"}

Reads a stream completely into memory. Supply a limit for untrusted streams.

```manuscript
fn read_all(input: ReadStream, max_bytes: Optional[Int] = none) -> Result[Bytes, IoError]:
```

## read_line {data-api-kind="Function"}

Reads one line, omitting its line ending; returns `none` at end of stream.

```manuscript
fn read_line(input: ReadStream, max_bytes: Optional[Int] = none) -> Result[Optional[String], IoError]:
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

