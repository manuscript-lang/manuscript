+++
title = "errors"
+++

# @std/errors.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/errors.ms"` remain supported.

## Error {data-api-kind="Interface"}

A contract for expected failures that can provide a human-readable message.

```manuscript
interface Error:
    fn message() -> String
```

