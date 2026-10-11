# Canonical standard-library declarations. Implementations are native.

import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type CsvOptions:
    delimiter: String
    line_ending: String

export fn parse(text: String, options: CsvOptions, max_rows: Int, max_cells: Int) -> Result[List[List[String]], LibraryError]

export fn stringify(rows: List[List[String]], options: CsvOptions, max_bytes: Int) -> Result[String, LibraryError]
