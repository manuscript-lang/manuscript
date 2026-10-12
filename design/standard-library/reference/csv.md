+++
title = "csv"
+++

# @std/csv.ms

Import each required symbol with `import Name from "@std/csv.ms"`.

## CsvOptions {data-api-kind="Record"}

```manuscript
type CsvOptions:
    delimiter: String
    line_ending: String
```

## parse {data-api-kind="Function"}

```manuscript
fn parse(text: String, options: CsvOptions, max_rows: Int, max_cells: Int) -> Result[List[List[String]], LibraryError]
```

## stringify {data-api-kind="Function"}

```manuscript
fn stringify(rows: List[List[String]], options: CsvOptions, max_bytes: Int) -> Result[String, LibraryError]
```

