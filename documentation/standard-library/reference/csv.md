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

### CsvError.InvalidData

Quoting or another CSV record syntax rule is violated by the input.

```manuscript
case InvalidData
```

### CsvError.InvalidInput

The delimiter, line ending or a supplied row/cell/output budget is invalid.

```manuscript
case InvalidInput
```

### CsvError.LimitExceeded

Parsed row/cell counts or the encoded output exceed a supplied budget.

```manuscript
case LimitExceeded
```

### CsvError.Error.message

Returns a CSV-prefixed diagnostic without exposing input cells or parser text.

```manuscript
fn message() -> String:
```

## CsvOptions {data-api-kind="Record"}

Delimiter and line ending used when parsing or writing CSV; defaults are comma and LF.

```manuscript
type CsvOptions:
    delimiter: String = ","
    line_ending: String = "\n"
```

### CsvOptions.delimiter

One non-NUL ASCII delimiter other than quote, CR or LF; defaults to comma.

```manuscript
delimiter: String = ","
```

### CsvOptions.line_ending

Row terminator for encoding, either LF or CRLF; defaults to LF.

```manuscript
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

