+++
title = "compress"
+++

# @std/compress.ms

Import each required symbol with `import Name from "@std/compress.ms"`.

## compress {data-api-kind="Function"}

```manuscript
fn compress(data: Bytes, format: String, level: Int, max_bytes: Int) -> Result[Bytes, LibraryError]
```

## decompress {data-api-kind="Function"}

```manuscript
fn decompress(data: Bytes, format: String, max_bytes: Int) -> Result[Bytes, LibraryError]
```

