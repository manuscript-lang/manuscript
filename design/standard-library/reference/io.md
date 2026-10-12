+++
title = "io"
+++

# @std/io.ms

Import each required symbol with `import Name from "@std/io.ms"`.

## File {data-api-kind="Interface"}

```manuscript
File: File
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## Files {data-api-kind="Interface"}

```manuscript
Files: Files
operation open: fn(path: String)->Result[File, IoError]
```

## IoError {data-api-kind="Alternative"}

```manuscript
IoError: IoError
case Closed
case InvalidInput
case Unavailable
case Failed(message: String)
```

## ReadStream {data-api-kind="Interface"}

```manuscript
ReadStream: ReadStream
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## WriteStream {data-api-kind="Interface"}

```manuscript
WriteStream: WriteStream
operation close: fn()->Unit
operation flush: fn()->Result[Unit, IoError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
```

## copy {data-api-kind="Function"}

```manuscript
copy: fn(input: ReadStream, output: WriteStream, max_bytes: Int)->Result[Int, LibraryError]
```

## read_all {data-api-kind="Function"}

```manuscript
read_all: fn(input: ReadStream, max_bytes: Int)->Result[Bytes, LibraryError]
```

## read_line {data-api-kind="Function"}

```manuscript
read_line: fn(input: ReadStream, max_bytes: Int)->Result[Optional[String], LibraryError]
```

