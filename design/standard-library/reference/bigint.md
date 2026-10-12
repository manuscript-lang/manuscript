+++
title = "bigint"
+++

# @std/bigint.ms

Import each required symbol with `import Name from "@std/bigint.ms"`.

## BigInt {data-api-kind="Interface"}

```manuscript
BigInt: BigInt
operation add: fn(right: BigInt)->BigInt
operation bit_and: fn(right: BigInt)->BigInt
operation bit_or: fn(right: BigInt)->BigInt
operation bit_xor: fn(right: BigInt)->BigInt
operation compare: fn(right: BigInt)->Int
operation divide: fn(right: BigInt)->Result[BigInt, LibraryError]
operation multiply: fn(right: BigInt)->BigInt
operation remainder: fn(right: BigInt)->Result[BigInt, LibraryError]
operation subtract: fn(right: BigInt)->BigInt
operation to_int: fn()->Optional[Int]
operation to_string: fn(radix: Int)->String
```

## add {data-api-kind="Function"}

```manuscript
add: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_and {data-api-kind="Function"}

```manuscript
bit_and: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_or {data-api-kind="Function"}

```manuscript
bit_or: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_xor {data-api-kind="Function"}

```manuscript
bit_xor: fn(left: BigInt, right: BigInt)->BigInt
```

## compare {data-api-kind="Function"}

```manuscript
compare: fn(left: BigInt, right: BigInt)->Int
```

## divide {data-api-kind="Function"}

```manuscript
divide: fn(left: BigInt, right: BigInt)->Result[BigInt, LibraryError]
```

## format {data-api-kind="Function"}

```manuscript
format: fn(value: BigInt, radix: Int)->String
```

## from_int {data-api-kind="Function"}

```manuscript
from_int: fn(value: Int)->BigInt
```

## multiply {data-api-kind="Function"}

```manuscript
multiply: fn(left: BigInt, right: BigInt)->BigInt
```

## parse {data-api-kind="Function"}

```manuscript
parse: fn(text: String, radix: Int, max_digits: Int)->Result[BigInt, LibraryError]
```

## remainder {data-api-kind="Function"}

```manuscript
remainder: fn(left: BigInt, right: BigInt)->Result[BigInt, LibraryError]
```

## subtract {data-api-kind="Function"}

```manuscript
subtract: fn(left: BigInt, right: BigInt)->BigInt
```

## to_int {data-api-kind="Function"}

```manuscript
to_int: fn(value: BigInt)->Optional[Int]
```

