+++
title = "compress"
+++

# @std/compress.ms

Import each required symbol with `import Name from "@std/compress.ms"`.

## CompressionError

Kind: alternative.

```text
CompressionError: CompressionError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
case Unsupported
case Failed(message: String)
operation message: fn()->String
```

## compress

Kind: fn.

```text
compress: fn(data: Bytes, format: String, level: Int, max_bytes: Int)->Result[Bytes, CompressionError]
```

## decompress

Kind: fn.

```text
decompress: fn(data: Bytes, format: String, max_bytes: Int)->Result[Bytes, CompressionError]
```

