# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned for malformed CSV input or configured size limits.
export type CsvError:
    # The delimiter, line ending or a supplied row/cell/output budget is invalid.
    case InvalidInput
    # Quoting or another CSV record syntax rule is violated by the input.
    case InvalidData
    # Parsed row/cell counts or the encoded output exceed a supplied budget.
    case LimitExceeded

# Delimiter and line ending used when parsing or writing CSV; defaults are comma and LF.
export type CsvOptions:
    # One non-NUL ASCII delimiter other than quote, CR or LF; defaults to comma.
    delimiter: String = ","
    # Row terminator for encoding, either LF or CRLF; defaults to LF.
    line_ending: String = "\n"

# Parses CSV into rows of cells, using fresh default options when omitted.
# Optional row and cell limits bound large inputs.
export fn parse(
    text: String,
    options: CsvOptions = CsvOptions(),
    max_rows: Optional[Int] = none,
    max_cells: Optional[Int] = none
) -> Result[List[List[String]], CsvError]:

# Encodes rows as CSV with comma delimiters and LF endings by default.
# Quotes cells when required by the delimiter or line ending.
export fn stringify(
    rows: List[List[String]],
    options: CsvOptions = CsvOptions(),
    max_bytes: Optional[Int] = none
) -> Result[String, CsvError]:

impl Error for CsvError:
    # Returns a CSV-prefixed diagnostic without exposing input cells or parser text.
    fn message() -> String:
