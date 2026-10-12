+++
title = "bigint"
+++

# @std/bigint.ms

Import each required symbol with `import Name from "@std/bigint.ms"`.

## BigInt

Kind: interface.

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

## add

Kind: fn.

```manuscript
add: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_and

Kind: fn.

```manuscript
bit_and: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_or

Kind: fn.

```manuscript
bit_or: fn(left: BigInt, right: BigInt)->BigInt
```

## bit_xor

Kind: fn.

```manuscript
bit_xor: fn(left: BigInt, right: BigInt)->BigInt
```

## compare

Kind: fn.

```manuscript
compare: fn(left: BigInt, right: BigInt)->Int
```

## divide

Kind: fn.

```manuscript
divide: fn(left: BigInt, right: BigInt)->Result[BigInt, LibraryError]
```

## format

Kind: fn.

```manuscript
format: fn(value: BigInt, radix: Int)->String
```

## from_int

Kind: fn.

```manuscript
from_int: fn(value: Int)->BigInt
```

## multiply

Kind: fn.

```manuscript
multiply: fn(left: BigInt, right: BigInt)->BigInt
```

## parse

Kind: fn.

```manuscript
parse: fn(text: String, radix: Int, max_digits: Int)->Result[BigInt, LibraryError]
```

## remainder

Kind: fn.

```manuscript
remainder: fn(left: BigInt, right: BigInt)->Result[BigInt, LibraryError]
```

## subtract

Kind: fn.

```manuscript
subtract: fn(left: BigInt, right: BigInt)->BigInt
```

## to_int

Kind: fn.

```manuscript
to_int: fn(value: BigInt)->Optional[Int]
```

