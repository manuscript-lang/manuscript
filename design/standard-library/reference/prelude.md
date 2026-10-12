+++
title = "prelude"
+++

# prelude

Intrinsic names; no import required.

## Bool

Kind: type.

```manuscript
Bool: Bool
```

## Equal

Kind: type.

```manuscript
Equal: Equal
```

## Float

Kind: type.

```manuscript
Float: Float
operation truncate_to_int: fn()->Optional[Int]
```

## Hashable

Kind: type.

```manuscript
Hashable: Hashable
```

## Int

Kind: type.

```manuscript
Int: Int
operation to_decimal: fn()->Decimal
operation to_float: fn()->Float
```

## Never

Kind: type.

```manuscript
Never: Never
```

## Shareable

Kind: type.

```manuscript
Shareable: Shareable
```

## String

Kind: type.

```manuscript
String: String
operation byte_length: fn()->Int
operation parse_int: fn()->Optional[Int]
operation to_bytes: fn()->Bytes
```

## Unit

Kind: type.

```manuscript
Unit: Unit
```

