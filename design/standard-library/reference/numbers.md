+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## format_exponential

Kind: fn.

```text
format_exponential: fn(value: Float, digits: Int)->Result[String, LibraryError]
```

## format_fixed

Kind: fn.

```text
format_fixed: fn(value: Float, digits: Int)->Result[String, LibraryError]
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

## format_precision

Kind: fn.

```text
format_precision: fn(value: Float, precision: Int)->Result[String, LibraryError]
```

## parse_float

Kind: fn.

```text
parse_float: fn(text: String)->Result[Float, LibraryError]
```

## parse_int

Kind: fn.

```text
parse_int: fn(text: String, radix: Int)->Result[Int, LibraryError]
```

