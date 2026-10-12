+++
title = "prelude"
+++

# prelude

Intrinsic names; no import required.

## Bool

Kind: type.

```text
Bool: Bool
```

## Equal

Kind: type.

```text
Equal: Equal
```

## Float

Kind: type.

```text
Float: Float
operation is_finite: fn()->Bool
operation is_nan: fn()->Bool
operation to_exponential: fn(digits: Int)->Result[String, LibraryError]
operation to_fixed: fn(digits: Int)->Result[String, LibraryError]
operation to_precision: fn(precision: Int)->Result[String, LibraryError]
operation to_string: fn()->String
operation truncate_to_int: fn()->Optional[Int]
```

## Hashable

Kind: type.

```text
Hashable: Hashable
```

## Int

Kind: type.

```text
Int: Int
operation to_decimal: fn()->Decimal
operation to_float: fn()->Float
operation to_string: fn(radix: Int)->String
```

## Never

Kind: type.

```text
Never: Never
```

## Shareable

Kind: type.

```text
Shareable: Shareable
```

## String

Kind: type.

```text
String: String
operation at: fn(index: Int)->Optional[String]
operation byte_length: fn()->Int
operation concat: fn(values: String)->String
operation contains: fn(text: String)->Bool
operation ends_with: fn(suffix: String)->Bool
operation index_of: fn(value: String)->Optional[Int]
operation last_index_of: fn(value: String)->Optional[Int]
operation lower: fn()->String
operation normalize: fn(form: String, max_bytes: Int)->Result[String, LibraryError]
operation pad_end: fn(target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
operation pad_start: fn(target_length: Int, padding: String, max_bytes: Int)->Result[String, LibraryError]
operation parse_int: fn()->Optional[Int]
operation repeat: fn(count: Int, max_bytes: Int)->Result[String, LibraryError]
operation replace: fn(old: String, new: String, max_replacements: Int)->String
operation replace_all: fn(old: String, new: String, max_bytes: Int)->Result[String, LibraryError]
operation scalar_at: fn(index: Int)->Optional[Int]
operation scalar_length: fn()->Int
operation scalar_values: fn()->List[Int]
operation slice: fn(start: Int, end: Int)->String
operation slice_scalars: fn(start: Int, end: Int)->Result[String, LibraryError]
operation split: fn(separator: String, max_parts: Int)->List[String]
operation starts_with: fn(prefix: String)->Bool
operation substring: fn(start: Int, end: Int)->String
operation to_bytes: fn()->Bytes
operation trim: fn()->String
operation trim_end: fn()->String
operation trim_start: fn()->String
operation upper: fn()->String
```

## Unit

Kind: type.

```text
Unit: Unit
```

