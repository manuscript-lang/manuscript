from "@std/string.ms" import StringBuilder
from "@std/collections.ms" import range

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
export def parse(
    text: String,
    options: CsvOptions = CsvOptions(),
    max_rows: Optional[Int] = none,
    max_cells: Optional[Int] = none
) -> Result[List[List[String]], CsvError]:
    let rows_budget = budget(max_rows)
    let cells_budget = budget(max_cells)
    if rows_budget < 0 or cells_budget < 0: return error(CsvError.InvalidInput)

    let valid = check_options(options)
    if valid.is_error(): return error(valid.err())

    var reader = Reader(
        lines: text.split("\n"), delimiter: options.delimiter.clone(), next_line: 0,
        total_lines: 0
    )

    # A final empty piece after the last newline is not a line.
    var count = reader.lines.length()
    if count > 0 and reader.lines[count - 1] == "": count -= 1
    reader.total_lines = count

    var rows = List[List[String]]()
    var cells = 0

    while True:
        let record = read_record(var reader)
        if record.is_error(): return error(record.err())

        let found = record.get()
        if not found.is_some(): break

        let row = found.get()
        if rows.length() >= rows_budget or row.length() > cells_budget - cells: return error(
            CsvError.LimitExceeded
        )

        cells += row.length()
        rows.append(row.clone())

    return ok(rows)

# The budget as a count, with no budget as a very large one and a negative budget as -1.
def budget(limit: Optional[Int]) -> Int:
    if let value = limit: return value

    return 9223372036854775807

# Delimiter: one ASCII scalar other than quote, CR, LF or NUL. Line ending: LF or CRLF.
def check_options(options: CsvOptions) -> Result[Unit, CsvError]:
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

    return ok(())

# Input split at LF; a record may span several lines when a quoted cell holds a newline.
type Reader:
    lines: List[String]
    delimiter: String
    next_line: Int
    total_lines: Int

# The next line without its CR terminator; none at end of input.
def take_line(var reader: Reader) -> Optional[String]:
    if reader.next_line >= reader.total_lines: return none

    var text = reader.lines[reader.next_line].clone()
    if text.ends_with("\r"): text = text.take(text.scalar_length() - 1)
    reader.next_line += 1
    return some(text)

# Reads the next record, skipping empty lines; none at end of input.
def read_record(var reader: Reader) -> Result[Optional[List[String]], CsvError]:
    var first = take_line(var reader)

    while True:
        if let candidate = first:
            if candidate != "": break

            first = take_line(var reader)
        else:
            return ok(none)

    var text = first.get().clone()

    # A line without quotes is one record whose cells are the delimiter-separated pieces.
    if not text.contains("\""): return ok(some(text.split(reader.delimiter)))

    # Splitting at quotes alternates unquoted and quoted pieces; an odd quote count means a
    # quoted cell continues on the next line.
    var pieces = text.split("\"")

    while pieces.length() % 2 == 0:
        let following = take_line(var reader)
        if not following.is_some(): return error(CsvError.InvalidData)

        text = f"{text}\n{following.get()}"
        pieces = text.split("\"")

    return ok(some(try record_of(pieces, reader.delimiter)))

# The cells of one record split at its quotes: pieces at odd positions are inside quotes.
def record_of(pieces: List[String], delimiter: String) -> Result[List[String], CsvError]:
    let last = pieces.length() - 1
    var row = List[String]()
    var cell = ""

    for index in range(0, pieces.length()):
        let piece = pieces[index]

        if index % 2 == 1:
            cell = cell.concat(piece)
            continue

        # A doubled quote is an empty unquoted piece between two quoted ones.
        if index > 0 and index < last and piece == "":
            cell = cell.concat("\"")
            continue

        if index > 0:
            if piece == "":
                row.append(cell.clone())
                break

            if not piece.starts_with(delimiter): return error(CsvError.InvalidData)

            row.append(cell.clone())

        let parts = piece.split(delimiter)
        var first = 0
        if index > 0: first = 1

        var cells_end = parts.length()
        if index < last: cells_end -= 1
        for part in range(first, cells_end):
            row.append(parts[part].clone())

        # A quote opens a cell only at its start.
        if index < last:
            if parts[cells_end] != "": return error(CsvError.InvalidData)

            cell = ""

    return ok(row)

# Encodes rows as CSV with comma delimiters and LF endings by default.
# Quotes cells when required by the delimiter or line ending.
export def stringify(
    rows: List[List[String]],
    options: CsvOptions = CsvOptions(),
    max_bytes: Optional[Int] = none
) -> Result[String, CsvError]:
    let limit = budget(max_bytes)
    if limit < 0: return error(CsvError.InvalidInput)

    let valid = check_options(options)
    if valid.is_error(): return error(valid.err())

    var out = StringBuilder()
    var used = 0
    let crlf = options.line_ending == "\r\n"
    let delimiter = options.delimiter.scalar_values() [0]

    for row in rows:
        var line = ""

        if row.length() == 1 and row[0] == "":
            line = "\"\""
        else:
            var pieces = List[String]()
            for field in row:
                pieces.append(encode_field(field, delimiter, crlf))
            line = pieces.join(options.delimiter)

        line = f"{line}{options.line_ending}"

        let size = line.byte_length()
        if size > limit - used: return error(CsvError.LimitExceeded)

        used += size
        out.append(line)

    return ok(out.build())

def needs_quotes(field: String, delimiter: Int) -> Bool:
    let scalars = field.scalar_values()
    if scalars.is_empty(): return False

    for scalar in scalars:
        if scalar == 34 or scalar == 13 or scalar == 10 or scalar == delimiter: return True

    let first = scalars[0]
    if first <= 32 or first >= 127: return field.get(0).trim() == ""

    return scalars.length() == 2 and first == 92 and scalars[1] == 46

def replaced(text: String, old: String, new: String) -> String:
    return text.replace(old, new)

def encode_field(field: String, delimiter: Int, crlf: Bool) -> String:
    if not needs_quotes(field, delimiter): return field.clone()

    var quoted = replaced(field, "\"", "\"\"")
    if crlf: quoted = replaced(replaced(quoted, "\r\n", "\n"), "\n", "\r\n")
    return f"\"{quoted}\""

impl Error for CsvError:
    # Returns a CSV-prefixed diagnostic without exposing input cells or parser text.
    def message() -> String:
        match self:
            case InvalidInput: return "CSV: invalid input"
            case InvalidData: return "CSV: invalid data"
            case LimitExceeded: return "CSV: limit exceeded"
