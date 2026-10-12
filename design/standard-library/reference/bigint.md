+++
title = "bigint"
+++

# @std/bigint.ms

Import each required symbol with `import Name from "@std/bigint.ms"`.

## BigInt

Kind: native.

```text
BigInt: BigInt
```

## add

Kind: fn.

```text
add: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_and

Kind: fn.

```text
bit_and: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_or

Kind: fn.

```text
bit_or: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_xor

Kind: fn.

```text
bit_xor: fn(left: BigInt, right: BigInt)->BigInt
```

## compare

Kind: fn.

```text
compare: fn(left: BigInt, right: BigInt)->Int
```

## divide

Kind: fn.

```text
divide: fn(left: BigInt, right: BigInt)->Result[BigInt, LibraryError]
```

## format

Kind: fn.

```text
format: fn(value: BigInt, radix: Int)->String
```

## from_int

Kind: fn.

```text
from_int: fn(value: Int)->BigInt
```

## multiply

Kind: fn.

```text
multiply: fn(left: BigInt, right: BigInt)->BigInt
```

## parse

Kind: fn.

```text
parse: fn(text: String, radix: Int, max_digits: Int)->Result[BigInt, LibraryError]
```

## remainder

Kind: fn.

```text
remainder: fn(left: BigInt, right: BigInt)->Result[BigInt, LibraryError]
```

## subtract

Kind: fn.

```text
subtract: fn(left: BigInt, right: BigInt)->BigInt
```

## to_int

Kind: fn.

```text
to_int: fn(value: BigInt)->Optional[Int]
```

