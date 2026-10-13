# Canonical standard-library declarations. Implementations are native.

import List from "@std/collections.ms"

# Errors returned for malformed CSV input or configured size limits.
export type CsvError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

# Delimiter and line ending used when parsing or writing CSV.
export type CsvOptions:
    delimiter: String
    line_ending: String

# Parses CSV into rows of cells. Optional row and cell limits bound large inputs.
export fn parse(
    text: String,
    options: CsvOptions,
    max_rows: Optional[Int] = none,
    max_cells: Optional[Int] = none
) -> Result[List[List[String]], CsvError]:

# Encodes rows as CSV, quoting cells when required by the delimiter or line ending.
export fn stringify(
    rows: List[List[String]],
    options: CsvOptions,
    max_bytes: Optional[Int] = none
) -> Result[String, CsvError]:

impl Error for CsvError:
    fn message() -> String:
