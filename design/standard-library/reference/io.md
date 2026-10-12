+++
title = "io"
+++

# @std/io.ms

Import each required symbol with `import Name from "@std/io.ms"`.

## File

Kind: contract.

```text
File: File
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## Files

Kind: contract.

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

Kind: contract.

```text
ReadStream: ReadStream
operation close: fn()->Unit
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
```

## WriteStream

Kind: contract.

```text
WriteStream: WriteStream
operation close: fn()->Unit
operation flush: fn()->Result[Unit, IoError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
```

