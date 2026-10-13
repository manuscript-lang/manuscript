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

Delimiter and line ending used when parsing or writing CSV; defaults are comma and LF.

```manuscript
type CsvOptions:
    delimiter: String = ","
    line_ending: String = "\n"
```

## parse {data-api-kind="Function"}

Parses CSV into rows of cells, using fresh default options when omitted.
Optional row and cell limits bound large inputs.

```manuscript
fn parse(text: String, options: CsvOptions = CsvOptions(), max_rows: Optional[Int] = none, max_cells: Optional[Int] = none) -> Result[List[List[String]], CsvError]:
```

## stringify {data-api-kind="Function"}

Encodes rows as CSV with comma delimiters and LF endings by default.
Quotes cells when required by the delimiter or line ending.

```manuscript
fn stringify(rows: List[List[String]], options: CsvOptions = CsvOptions(), max_bytes: Optional[Int] = none) -> Result[String, CsvError]:
```

