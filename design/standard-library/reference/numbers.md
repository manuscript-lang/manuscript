+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## NumberError

Kind: alternative.

```text
NumberError: NumberError
implements: Error
case InvalidInput
case InvalidData
case OutOfRange
operation message: fn()->String
```

## format_float

Kind: fn.

```text
format_float: fn(value: Float)->String
```

## format_int

Kind: fn.

```text
format_int: fn(value: Int, radix: Int)->String
```

## parse_float

Kind: fn.

```text
parse_float: fn(text: String)->Result[Float, NumberError]
```

## parse_int

Kind: fn.

```text
parse_int: fn(text: String, radix: Int)->Result[Int, NumberError]
```

