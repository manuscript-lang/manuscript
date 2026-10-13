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

### CompressionError.Failed

An explicit implementation-supplied compression diagnostic; native codecs use specific cases.

```manuscript
case Failed(message: String)
```

### CompressionError.InvalidData

Compressed framing, checksum, payload or trailing data is invalid for the chosen format.

```manuscript
case InvalidData
```

### CompressionError.InvalidInput

Compression level is outside 0..9, or a supplied encoded/decoded byte budget is negative.

```manuscript
case InvalidInput
```

### CompressionError.LimitExceeded

Encoded or decompressed output exceeds the supplied byte budget.

```manuscript
case LimitExceeded
```

### CompressionError.Unsupported

A String selector is not exactly gzip, zlib or deflate; typed selectors avoid spelling errors.

```manuscript
case Unsupported
```

### CompressionError.Failed.message

Original diagnostic text, returned unchanged by message().

```manuscript
message: String
```

### CompressionError.Error.message

Returns original Failed text, or a compression-prefixed diagnostic for other cases.

```manuscript
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

DEFLATE data wrapped in GZIP headers and a checksum trailer.

```manuscript
case Gzip
```

### CompressionFormat.Zlib

DEFLATE data with ZLIB header and Adler-32 checksum framing.

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

