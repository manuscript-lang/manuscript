+++
title = "equality"
+++

# @std/equality.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/equality.ms"` remain supported.

## Equal {data-api-kind="Interface"}

```manuscript
interface Equal:
    fn equals(other: Equal) -> Bool
```

## Hashable {data-api-kind="Interface"}

```manuscript
interface Hashable:
    fn hash() -> Int
```

