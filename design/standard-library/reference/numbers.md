+++
title = "numbers"
+++

# @std/numbers.ms

Import each required symbol with `import Name from "@std/numbers.ms"`.

## format_exponential {data-api-kind="Function"}

```manuscript
format_exponential: fn(value: Float, digits: Int)->Result[String, LibraryError]
```

## format_fixed {data-api-kind="Function"}

```manuscript
format_fixed: fn(value: Float, digits: Int)->Result[String, LibraryError]
```

## format_float {data-api-kind="Function"}

```manuscript
format_float: fn(value: Float)->String
```

## format_int {data-api-kind="Function"}

```manuscript
format_int: fn(value: Int, radix: Int)->String
```

## format_precision {data-api-kind="Function"}

```manuscript
format_precision: fn(value: Float, precision: Int)->Result[String, LibraryError]
```

## parse_float {data-api-kind="Function"}

```manuscript
parse_float: fn(text: String)->Result[Float, LibraryError]
```

## parse_int {data-api-kind="Function"}

```manuscript
parse_int: fn(text: String, radix: Int)->Result[Int, LibraryError]
```

