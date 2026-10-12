# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type CsvError:
    case InvalidInput
    case InvalidData
    case LimitExceeded

export type CsvOptions:
    delimiter: String
    line_ending: String

export fn parse(
    text: String,
    options: CsvOptions,
    max_rows: Optional[Int] = none,
    max_cells: Optional[Int] = none
) -> Result[List[List[String]], CsvError]:

export fn stringify(
    rows: List[List[String]],
    options: CsvOptions,
    max_bytes: Optional[Int] = none
) -> Result[String, CsvError]:

impl Error for CsvError:
    fn message() -> String:
