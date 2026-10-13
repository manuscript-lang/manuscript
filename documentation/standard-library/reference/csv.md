+++
title = "csv"
+++

# @std/csv.ms

Import each required symbol with `import Name from "@std/csv.ms"`.

## CsvError {data-api-kind="Alternative"}

Errors returned for malformed CSV input or configured size limits.

```manuscript
type CsvError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
```

```manuscript
impl Error for CsvError:
    fn message() -> String:
```

## CsvOptions {data-api-kind="Record"}

Delimiter and line ending used when parsing or writing CSV.

```manuscript
type CsvOptions:
    delimiter: String
    line_ending: String
```

## parse {data-api-kind="Function"}

Parses CSV into rows of cells. Optional row and cell limits bound large inputs.

```manuscript
fn parse(text: String, options: CsvOptions, max_rows: Optional[Int] = none, max_cells: Optional[Int] = none) -> Result[List[List[String]], CsvError]:
```

## stringify {data-api-kind="Function"}

Encodes rows as CSV, quoting cells when required by the delimiter or line ending.

```manuscript
fn stringify(rows: List[List[String]], options: CsvOptions, max_bytes: Optional[Int] = none) -> Result[String, CsvError]:
```

