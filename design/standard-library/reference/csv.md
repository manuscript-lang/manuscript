+++
title = "csv"
+++

# @std/csv.ms

Import each required symbol with `import Name from "@std/csv.ms"`.

## CsvError

Kind: alternative.

```text
CsvError: CsvError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
operation message: fn()->String
```

## CsvOptions

Kind: record.

```text
CsvOptions: CsvOptions
field delimiter: String
field line_ending: String
```

## parse

Kind: fn.

```text
parse: fn(text: String, options: CsvOptions, max_rows: Int, max_cells: Int)->Result[List[List[String]], CsvError]
```

## stringify

Kind: fn.

```text
stringify: fn(rows: List[List[String]], options: CsvOptions, max_bytes: Int)->Result[String, CsvError]
```

