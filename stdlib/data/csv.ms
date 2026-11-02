import StringBuilder from "@std/string.ms"
import Bytes from "@std/bytes.ms"

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
    max_rows: Int?,
    max_cells: Int?
) List[List[String]]!CsvError:
    let rows_budget = budget(max_rows)
    let cells_budget = budget(max_cells)
    if rows_budget < 0 or cells_budget < 0: return error(CsvError.InvalidInput)

    let valid = check_options(options)
    if valid.is_error(): return error(valid.err())

    let bytes = text.to_bytes()
    let total = bytes.length()
    var reader = Reader(
        bytes: bytes, total: total,
        delimiter: options.delimiter.scalar_values()[0].to_uint8().get(0),
        delimiter_text: options.delimiter.clone(), at: 0, quote: -1, delimiter_at: -1,
        line_at: -1
    )
    var rows = List[List[String]]()
    var cells = 0

    while true:
        let record = reader.read_record()
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
fn budget(limit: Int?) Int:
    if let value = limit: return value

    return 9223372036854775807

# Delimiter: one ASCII scalar other than quote, CR, LF or NUL. Line ending: LF or CRLF.
fn check_options(options: CsvOptions) Unit!CsvError:
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

# The input as bytes with a cursor. The cached offsets are the next quote, delimiter and LF at or
# after the cursor, or total when there is none; they are searched again only once passed.
type Reader:
    bytes: Bytes
    total: Int
    delimiter: UInt8
    delimiter_text: String
    at: Int
    quote: Int
    delimiter_at: Int
    line_at: Int

impl Reader:
    var fn next_quote(from: Int) Int:
        if self.quote < from: self.quote = self.bytes.index_of_byte(34, from).get(
            self.total
        )
        return self.quote

    var fn next_delimiter(from: Int) Int:
        if self.delimiter_at < from: self.delimiter_at = self.bytes.index_of_byte(
            self.delimiter, from
        ).get(self.total)
        return self.delimiter_at

    var fn next_line(from: Int) Int:
        if self.line_at < from: self.line_at = self.bytes.index_of_byte(10, from).get(
            self.total
        )
        return self.line_at

    fn text_between(start: Int, end: Int) String:
        if let text = self.bytes.decode_utf8_range(start, end): return text

        return ""

    # The offset just past the line ending at the cursor, or the cursor when the cursor is not at one.
    fn line_end_after(at: Int) Int:
        if at >= self.total: return at

        let byte = self.bytes[at]
        if byte == 10: return at + 1
        if byte == 13 and at + 1 >= self.total: return at + 1
        if byte == 13 and self.bytes[at + 1] == 10: return at + 2

        return at

    # Reads the next record, skipping empty lines; none at end of input.
    var fn read_record() List[String]?!CsvError:
        while true:
            let skipped = self.line_end_after(self.at)
            if skipped == self.at: break

            self.at = skipped

        if self.at >= self.total: return ok(none)

        # A line without quotes is one record whose cells are the delimiter-separated pieces.
        let line = self.next_line(self.at)

        if self.next_quote(self.at) > line:
            var last = line
            if last > self.at and self.bytes[last - 1] == 13: last -= 1

            let text = self.text_between(self.at, last)
            self.at = line
            if line < self.total: self.at = line + 1
            return ok(text.split(self.delimiter_text))

        var row = List[String]()

        while true:
            var cell = ""
            var at = self.at.to_int()

            if at < self.total and self.bytes[at] == 34:
                at += 1

                while true:
                    let close = self.next_quote(at)
                    if close >= self.total: return error(CsvError.InvalidData)

                    cell = cell.concat(self.text_between(at, close))
                    at = close + 1

                    if at < self.total and self.bytes[at] == 34:
                        cell = cell.concat("\"")
                        at += 1
                        continue

                    break

                if cell.contains("\r\n"): cell = cell.replace("\r\n", "\n")

                let ended = self.line_end_after(at)

                if at >= self.total or ended > at:
                    row.append(cell)
                    self.at = ended
                    return ok(row)

                if self.bytes[at] != self.delimiter: return error(CsvError.InvalidData)

                row.append(cell)
                self.at = at + 1
                continue

            let stop = self.next_delimiter(at)
            let newline = self.next_line(at)
            var end = stop
            if newline < stop: end = newline
            if self.next_quote(at) < end: return error(CsvError.InvalidData)

            if end < stop or stop >= self.total:
                # The cell closes the record; drop the CR of a CRLF ending.
                var last = end
                if last > at and self.bytes[last - 1] == 13: last -= 1
                row.append(self.text_between(at, last))
                self.at = end
                if end < self.total: self.at = end + 1
                return ok(row)

            row.append(self.text_between(at, end))
            self.at = end + 1

# Encodes rows as CSV with comma delimiters and LF endings by default.
# Quotes cells when required by the delimiter or line ending.
export fn stringify(
    rows: List[List[String]],
    options: CsvOptions = CsvOptions(),
    max_bytes: Int?
) String!CsvError:
    let limit = budget(max_bytes)
    if limit < 0: return error(CsvError.InvalidInput)

    let valid = check_options(options)
    if valid.is_error(): return error(valid.err())

    var out = StringBuilder()
    var used = 0
    let crlf = options.line_ending == "\r\n"
    let delimiter = options.delimiter.scalar_values()[0]

    for row in rows:
        var line = ""

        if row.length() == 1 and row[0] == "":
            line = "\"\""
        else:
            var pieces = List[String]()
            for field in row:
                pieces.append(encode_field(field, delimiter, crlf))
            line = pieces.join(options.delimiter)

        line = "{line}{options.line_ending}"

        let size = line.byte_length()
        if size > limit - used: return error(CsvError.LimitExceeded)

        used += size
        out.append(line)

    return ok(out.build())

fn needs_quotes(field: String, delimiter: Int) Bool:
    let scalars = field.scalar_values()
    if scalars.is_empty(): return false

    for scalar in scalars:
        if scalar == 34 or scalar == 13 or scalar == 10 or scalar == delimiter: return true

    let first = scalars[0]
    if first <= 32 or first >= 127: return field.get(0).trim() == ""

    return scalars.length() == 2 and first == 92 and scalars[1] == 46

fn replaced(text: String, old: String, new: String) String:
    return text.replace(old, new)

fn encode_field(field: String, delimiter: Int, crlf: Bool) String:
    if not needs_quotes(field, delimiter): return field.clone()

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
