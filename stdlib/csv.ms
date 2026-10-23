import {StringBuilder} from "@std/string.ms"
import {range} from "@std/collections.ms"

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
) Result[List[List[String]], CsvError]:
    let rows_budget = budget(max_rows)
    let cells_budget = budget(max_cells)
    if rows_budget < 0 or cells_budget < 0: return error(CsvError.InvalidInput)

    let valid = check_options(options)
    if valid.is_error(): return error(valid.err())

    var reader = Reader(
        lines: text.split("\n"), delimiter: options.delimiter, next_line: 0,
        total_lines: 0
    )
    # A final empty piece after the last newline is not a line.
    var count = reader.lines.length()
    if count > 0 and reader.lines[count - 1] == "": count -= 1
    reader.total_lines = count
    var rows = List[List[String]]()
    var cells = 0

    while true:
        let record = read_record(var reader)
        if record.is_error(): return error(record.err())

        let found = record.get()
        if not found.is_some(): break

        let row = found.get()
        if rows.length() >= rows_budget or row.length() > cells_budget - cells: return error(
            CsvError.LimitExceeded
        )

        cells += row.length()
        rows.append(row)

    return ok(rows)

# The budget as a count, with no budget as a very large one and a negative budget as -1.
fn budget(limit: Optional[Int]) Int:
    if let value = limit: return value

    return 9223372036854775807

# Delimiter: one ASCII scalar other than quote, CR, LF or NUL. Line ending: LF or CRLF.
fn check_options(options: CsvOptions) Result[Unit, CsvError]:
    let scalars = options.delimiter.scalar_values()
    if scalars.length() != 1: return error(CsvError.InvalidInput)

    let delimiter = scalars[0]
    if (
        delimiter == 0
        or delimiter >= 128
        or delimiter == 34
        or delimiter == 13
        or delimiter == 10
    ): return error(CsvError.InvalidInput)
    if options.line_ending != "\n" and options.line_ending != "\r\n": return error(
        CsvError.InvalidInput
    )

    return ok(unit)

# Input split at LF; a record may span several lines when a quoted cell holds a newline.
type Reader:
    lines: List[String]
    delimiter: String
    next_line: Int
    total_lines: Int

# One line without its CR terminator, as scalars.
type Line:
    cells: List[String]
    length: Int
    ended: Bool

fn take_line(var reader: Reader) Optional[Line]:
    if reader.next_line >= reader.total_lines: return none

    let cells = reader.lines[reader.next_line].chars()
    var length = cells.length()
    if length > 0 and cells[length - 1] == "\r": length -= 1
    reader.next_line += 1
    return some(
        Line(
            cells: cells, length: length,
            ended: reader.next_line < reader.lines.length()
        )
    )

# Reads the next record, skipping empty lines; none at end of input.
fn read_record(var reader: Reader) Result[Optional[List[String]], CsvError]:
    var first = take_line(var reader)

    while true:
        if let candidate = first:
            if candidate.length > 0: break

            first = take_line(var reader)
        else:
            return ok(none)

    var line = first.get()
    var row = List[String]()
    var cell = StringBuilder()
    var at = 0

    while true:
        if at >= line.length or line.cells[at] != "\"":
            var stop = at

            while stop < line.length and line.cells[stop] != reader.delimiter:
                if line.cells[stop] == "\"": return error(CsvError.InvalidData)

                stop += 1

            for index in range(at, stop):
                cell.append(line.cells[index])
            row.append(cell.freeze())
            cell = StringBuilder()
            if stop >= line.length: break

            at = stop + 1
            continue

        at += 1

        while true:
            var close = at
            while close < line.length and line.cells[close] != "\"": close += 1

            if close >= line.length:
                if not line.ended: return error(CsvError.InvalidData)

                for index in range(at, line.length):
                    cell.append(line.cells[index])
                cell.append("\n")
                let following = take_line(var reader)
                if not following.is_some(): return error(CsvError.InvalidData)

                line = following.get()
                at = 0
                continue

            for index in range(at, close):
                cell.append(line.cells[index])
            at = close + 1

            if at >= line.length:
                row.append(cell.freeze())
                return ok(some(row))

            if line.cells[at] == "\"":
                cell.append("\"")
                at += 1
                continue

            if line.cells[at] != reader.delimiter: return error(CsvError.InvalidData)

            at += 1
            row.append(cell.freeze())
            cell = StringBuilder()
            break

    return ok(some(row))

# Encodes rows as CSV with comma delimiters and LF endings by default.
# Quotes cells when required by the delimiter or line ending.
export fn stringify(
    rows: List[List[String]],
    options: CsvOptions = CsvOptions(),
    max_bytes: Optional[Int] = none
) Result[String, CsvError]:
    let limit = budget(max_bytes)
    if limit < 0: return error(CsvError.InvalidInput)

    let valid = check_options(options)
    if valid.is_error(): return error(valid.err())

    var out = StringBuilder()
    var used = 0
    let crlf = options.line_ending == "\r\n"

    for row in rows:
        var line = ""

        if row.length() == 1 and row[0] == "":
            line = "\"\""
        else:
            var pieces = List[String]()
            for field in row:
                pieces.append(encode_field(field, options.delimiter, crlf))
            line = pieces.join(options.delimiter)

        line = "{line}{options.line_ending}"
        let size = line.byte_length()
        if size > limit - used: return error(CsvError.LimitExceeded)

        used += size
        out.append(line)

    return ok(out.freeze())

fn needs_quotes(field: String, delimiter: String) Bool:
    if field == "": return false
    if field == "\\.": return true
    if field.contains("\"") or field.contains("\r") or field.contains("\n"): return true
    if field.contains(delimiter): return true

    return field.get(0).trim() == ""

fn replaced(text: String, old: String, new: String) String:
    if let result = text.replace_all(old, new): return result

    return text

fn encode_field(field: String, delimiter: String, crlf: Bool) String:
    if not needs_quotes(field, delimiter): return field

    var quoted = replaced(field, "\"", "\"\"")
    if crlf: quoted = replaced(replaced(quoted, "\r\n", "\n"), "\n", "\r\n")
    return "\"{quoted}\""

impl Error for CsvError:
    # Returns a CSV-prefixed diagnostic without exposing input cells or parser text.
    fn message() String:
        match self:
            InvalidInput: return "CSV: invalid input"
            InvalidData: return "CSV: invalid data"
            LimitExceeded: return "CSV: limit exceeded"
