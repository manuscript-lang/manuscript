+++
title = "compress"
+++

# @std/compress.ms

Import each required symbol with `import Name from "@std/compress.ms"`.

## compress

Kind: fn.

```manuscript
compress: fn(data: Bytes, format: String, level: Int, max_bytes: Int)->Result[Bytes, LibraryError]
```

## decompress

Kind: fn.

```manuscript
decompress: fn(data: Bytes, format: String, max_bytes: Int)->Result[Bytes, LibraryError]
```

