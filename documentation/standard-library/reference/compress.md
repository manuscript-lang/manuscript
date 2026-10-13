+++
title = "compress"
+++

# @std/compress.ms

Import each required symbol with `import Name from "@std/compress.ms"`.

## CompressionError {data-api-kind="Alternative"}

Errors returned when compressed data is unsupported, invalid, or exceeds a limit.

```manuscript
type CompressionError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)
```

```manuscript
impl Error for CompressionError:
    fn message() -> String:
```

## compress {data-api-kind="Function"}

Compresses bytes using `gzip`, `zlib`, or `deflate` at the requested level.
`max_bytes` bounds the encoded output when supplied.

```manuscript
fn compress(data: Bytes, format: String, level: Int, max_bytes: Optional[Int] = none) -> Result[Bytes, CompressionError]:
```

## decompress {data-api-kind="Function"}

Decompresses supported data and stops when the supplied output limit is reached.

```manuscript
fn decompress(data: Bytes, format: String, max_bytes: Optional[Int] = none) -> Result[Bytes, CompressionError]:
```

