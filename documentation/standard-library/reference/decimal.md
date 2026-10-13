+++
title = "decimal"
+++

# @std/decimal.ms

Import each required symbol with `import Name from "@std/decimal.ms"`.

## Decimal {data-api-kind="Native type"}

An exact decimal value. Conversions are explicit because binary floats may round.

```manuscript
type Decimal:
    fn to_float() -> Float:
    fn truncate_to_int() -> Optional[Int]:
```

