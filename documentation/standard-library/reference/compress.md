+++
title = "compress"
+++

# @std/compress.ms

Import each required symbol with `import Name from "@std/compress.ms"`.

## CompressionError {data-api-kind="Alternative"}

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

```manuscript
fn compress(data: Bytes, format: String, level: Int, max_bytes: Optional[Int] = none) -> Result[Bytes, CompressionError]:
```

## decompress {data-api-kind="Function"}

```manuscript
fn decompress(data: Bytes, format: String, max_bytes: Optional[Int] = none) -> Result[Bytes, CompressionError]:
```

