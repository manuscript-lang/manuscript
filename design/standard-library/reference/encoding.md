+++
title = "encoding"
+++

# @std/encoding.ms

Import each required symbol with `import Name from "@std/encoding.ms"`.

## base64_decode {data-api-kind="Function"}

```manuscript
fn base64_decode(text: String, url_safe: Bool, max_bytes: Int) -> Result[Bytes, LibraryError]
```

## base64_encode {data-api-kind="Function"}

```manuscript
fn base64_encode(data: Bytes, url_safe: Bool) -> String
```

## hex_decode {data-api-kind="Function"}

```manuscript
fn hex_decode(text: String, max_bytes: Int) -> Result[Bytes, LibraryError]
```

## hex_encode {data-api-kind="Function"}

```manuscript
fn hex_encode(data: Bytes) -> String
```

