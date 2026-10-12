+++
title = "io"
+++

# @std/io.ms

Import each required symbol with `import Name from "@std/io.ms"`.

## File {data-api-kind="Interface"}

```manuscript
interface File:
    fn close() -> Unit
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
```

## Files {data-api-kind="Interface"}

```manuscript
interface Files:
    fn open(path: String) -> Result[File, IoError]
```

## IoError {data-api-kind="Alternative"}

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
    fn message() -> String
```

## ReadStream {data-api-kind="Interface"}

```manuscript
interface ReadStream:
    fn close() -> Unit
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
```

## WriteStream {data-api-kind="Interface"}

```manuscript
interface WriteStream:
    fn close() -> Unit
    fn flush() -> Result[Unit, IoError]
    fn write(data: Bytes) -> Result[Unit, IoError]
```

## copy {data-api-kind="Function"}

```manuscript
fn copy(input: ReadStream, output: WriteStream, max_bytes: Int) -> Result[Int, IoError]
```

## read_all {data-api-kind="Function"}

```manuscript
fn read_all(input: ReadStream, max_bytes: Int) -> Result[Bytes, IoError]
```

## read_line {data-api-kind="Function"}

```manuscript
fn read_line(input: ReadStream, max_bytes: Int) -> Result[Optional[String], IoError]
```

