+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## format_float

Kind: fn.

```manuscript
format_float: fn(value: Float)->String
```

## format_int

Kind: fn.

```manuscript
format_int: fn(value: Int, radix: Int)->String
```

## parse_float

Kind: fn.

```manuscript
parse_float: fn(text: String)->Result[Float, LibraryError]
```

## parse_int

Kind: fn.

```manuscript
parse_int: fn(text: String, radix: Int)->Result[Int, LibraryError]
```

