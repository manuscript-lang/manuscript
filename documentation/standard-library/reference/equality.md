+++
title = "equality"
+++

# @std/equality.ms

Import each required symbol with `import Name from "@std/equality.ms"`.

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

