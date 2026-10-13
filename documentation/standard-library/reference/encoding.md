+++
title = "encoding"
+++

# @std/encoding.ms

Import each required symbol with `import Name from "@std/encoding.ms"`.

## EncodingError {data-api-kind="Alternative"}

Errors returned when encoded text is invalid or exceeds a supplied byte limit.

```manuscript
type EncodingError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for EncodingError:
    fn message() -> String:
```

## base64_decode {data-api-kind="Function"}

Decodes standard Base64 by default; set `url_safe: true` for the URL-safe alphabet.

```manuscript
fn base64_decode(text: String, url_safe: Bool = false, max_bytes: Optional[Int64] = none) -> Result[Bytes, EncodingError]:
```

## base64_encode {data-api-kind="Function"}

Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text.

```manuscript
fn base64_encode(data: Bytes, url_safe: Bool = false) -> String:
```

## hex_decode {data-api-kind="Function"}

Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.

```manuscript
fn hex_decode(text: String, max_bytes: Optional[Int64] = none) -> Result[Bytes, EncodingError]:
```

## hex_encode {data-api-kind="Function"}

Encodes each byte as two lowercase hexadecimal digits.

```manuscript
fn hex_encode(data: Bytes) -> String:
```

