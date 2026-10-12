+++
title = "encoding"
+++

# @std/encoding.ms

Import each required symbol with `import Name from "@std/encoding.ms"`.

## base64_decode

Kind: fn.

```text
base64_decode: fn(text: String, url_safe: Bool, max_bytes: Int)->Result[Bytes, LibraryError]
```

## base64_encode

Kind: fn.

```text
base64_encode: fn(data: Bytes, url_safe: Bool)->String
```

## hex_decode

Kind: fn.

```text
hex_decode: fn(text: String, max_bytes: Int)->Result[Bytes, LibraryError]
```

## hex_encode

Kind: fn.

```text
hex_encode: fn(data: Bytes)->String
```

