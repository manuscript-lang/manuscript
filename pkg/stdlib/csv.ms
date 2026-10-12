# Canonical standard-library declarations. Implementations are native.

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

export fn parse(text: String, options: CsvOptions, max_rows: Int, max_cells: Int) -> Result[List[List[String]], CsvError]

export fn stringify(rows: List[List[String]], options: CsvOptions, max_bytes: Int) -> Result[String, CsvError]

impl Error for CsvError:
    fn message() -> String
