+++
title = "io"
+++

# @std/io.ms

Import each required symbol with `import Name from "@std/io.ms"`.

## File

Kind: interface.

```text
File: File
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## Files

Kind: interface.

```text
Files: Files
operation open: fn(path: String)->Result[File & Shareable, IoError]
```

## IoError

Kind: alternative.

```text
IoError: IoError
case Closed
case InvalidInput
case Unavailable
case Failed(message: String)
```

## ReadStream

Kind: interface.

```text
ReadStream: ReadStream
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## WriteStream

Kind: interface.

```text
WriteStream: WriteStream
operation close: fn()->Unit
operation flush: fn()->Result[Unit, IoError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
```

## copy

Kind: fn.

```text
copy: fn(input: ReadStream & Shareable, output: WriteStream & Shareable, max_bytes: Int)->Result[Int, LibraryError]
```

## read_all

Kind: fn.

```text
read_all: fn(input: ReadStream & Shareable, max_bytes: Int)->Result[Bytes, LibraryError]
```

## read_line

Kind: fn.

```text
read_line: fn(input: ReadStream & Shareable, max_bytes: Int)->Result[Optional[String], LibraryError]
```

