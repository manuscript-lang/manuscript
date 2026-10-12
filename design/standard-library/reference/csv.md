+++
title = "csv"
+++

# @std/csv.ms

Import each required symbol with `import Name from "@std/csv.ms"`.

## CsvOptions {data-api-kind="Record"}

```manuscript
CsvOptions: CsvOptions
field delimiter: String
field line_ending: String
```

## parse {data-api-kind="Function"}

```manuscript
parse: fn(text: String, options: CsvOptions, max_rows: Int, max_cells: Int)->Result[List[List[String]], LibraryError]
```

## stringify {data-api-kind="Function"}

```manuscript
stringify: fn(rows: List[List[String]], options: CsvOptions, max_bytes: Int)->Result[String, LibraryError]
```

