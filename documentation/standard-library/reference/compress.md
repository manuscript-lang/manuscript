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

## CompressionFormat {data-api-kind="Alternative"}

Selects a supported compression format; Deflate is raw DEFLATE without a wrapper.
Existing compress/decompress format: String calls remain available.

```manuscript
type CompressionFormat:
    case Gzip
    case Zlib
    case Deflate
    fn compress(data: Bytes, level: Int, max_bytes: Optional[Int64] = none) -> Result[Bytes, CompressionError]:
    fn decompress(data: Bytes, max_bytes: Optional[Int64] = none) -> Result[Bytes, CompressionError]:
```

### CompressionFormat.Deflate

Raw DEFLATE without framing.

```manuscript
case Deflate
```

### CompressionFormat.Gzip

GZIP framing.

```manuscript
case Gzip
```

### CompressionFormat.Zlib

ZLIB framing.

```manuscript
case Zlib
```

### CompressionFormat.compress

Compresses with level 0..9 and the same optional output budget/domain errors as compress.

```manuscript
fn compress(data: Bytes, level: Int, max_bytes: Optional[Int64] = none) -> Result[Bytes, CompressionError]:
```

### CompressionFormat.decompress

Decompresses with the same cumulative output limit and validation as decompress.

```manuscript
fn decompress(data: Bytes, max_bytes: Optional[Int64] = none) -> Result[Bytes, CompressionError]:
```

## compress {data-api-kind="Function"}

Compresses using exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive).
Other formats return Unsupported; level must be 0..9 (0 stores data), else InvalidInput.
`max_bytes` bounds the encoded output when supplied.

```manuscript
fn compress(data: Bytes, format: String, level: Int, max_bytes: Optional[Int64] = none) -> Result[Bytes, CompressionError]:
```

## decompress {data-api-kind="Function"}

Decompresses exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive); others return Unsupported.
Stops when the supplied output limit is reached.

```manuscript
fn decompress(data: Bytes, format: String, max_bytes: Optional[Int64] = none) -> Result[Bytes, CompressionError]:
```

