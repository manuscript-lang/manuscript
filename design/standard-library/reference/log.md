+++
title = "log"
+++

# @std/log.ms

Import each required symbol with `import Name from "@std/log.ms"`.

## write

Kind: fn.

```text
write: fn(output: WriteStream & Shareable, level: String, message: String, fields: Map[String, String], max_bytes: Int)->Result[Unit, LibraryError]
```

