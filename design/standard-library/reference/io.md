+++
title = "io"
+++

# @std/io.ms

Import each required symbol with `import Name from "@std/io.ms"`.

## File

Kind: interface.

```manuscript
File: File
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## Files

Kind: interface.

```manuscript
Files: Files
operation open: fn(path: String)->Result[File, IoError]
```

## IoError

Kind: alternative.

```manuscript
IoError: IoError
case Closed
case InvalidInput
case Unavailable
case Failed(message: String)
```

## ReadStream

Kind: interface.

```manuscript
ReadStream: ReadStream
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## WriteStream

Kind: interface.

```manuscript
WriteStream: WriteStream
operation close: fn()->Unit
operation flush: fn()->Result[Unit, IoError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
```

## copy

Kind: fn.

```manuscript
copy: fn(input: ReadStream, output: WriteStream, max_bytes: Int)->Result[Int, LibraryError]
```

## read_all

Kind: fn.

```manuscript
read_all: fn(input: ReadStream, max_bytes: Int)->Result[Bytes, LibraryError]
```

## read_line

Kind: fn.

```manuscript
read_line: fn(input: ReadStream, max_bytes: Int)->Result[Optional[String], LibraryError]
```

