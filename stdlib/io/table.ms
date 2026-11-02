import max, min from "@std/math/math.ms"
import StringBuilder from "@std/string.ms"
import msstd_table_cell_width from "@std/internal/table.ms"

# Horizontal placement of a cell within its column's measured display width.
# Example: `format([["name", "count"], ["tea", "2"]], [Alignment.Left, Alignment.Right])`.
export type Alignment:
    # Places unused column space after the cell.
    case Left
    # Places unused column space before the cell.
    case Right
    # Splits unused space, putting an odd extra space after the cell.
    case Center

# Errors from pure table formatting; no terminal or other host service is accessed.
export type TableError:
    # Negative padding/budget, or a nonempty alignment list with the wrong column count.
    case InvalidInput
    # Rows differ in cell count, or a cell contains a control, tab, line break or ANSI escape.
    case InvalidData
    # A row/cell/output budget or the native string byte limit would be exceeded.
    case LimitExceeded

# Borrows rectangular rows of complete strings without wrapping, truncating, or normalizing cells.
# Callers may format and inspect the same rows afterward without cloning them.
# Example: `format([["name", "count"], ["tea", "2"]], [Alignment.Left, Alignment.Right])`.
# Returns LF-separated rows with no final LF and no added trailing padding in the last column.
# An empty table formats as ""; zero-cell rows are blank lines.
# Empty alignments means left alignment; otherwise supply one alignment per column.
# Padding is the nonnegative number of spaces between columns (default 2).
# Unicode sequence widths use unicode-width with ambiguous characters narrow: combining marks,
# wide characters and supported emoji sequences are measured together; cell bytes stay intact.
# Widths are estimates, not a promise for every font, script or terminal. Controls (including
# tabs, CR/LF, ANSI ESC and C1), U+2028 and U+2029 are rejected, never expanded or interpreted.
# Optional limits count input rows, total cells and UTF-8 output bytes; none adds no budget.
# Negative budgets return InvalidInput; exhaustion returns LimitExceeded without partial output.
export fn format(
    rows: List[List[String]],
    alignments: List[Alignment] = [],
    padding: Int = 2,
    max_rows: Int?,
    max_cells: Int?,
    max_bytes: Int?
) String!TableError:
    let row_limit = try budget(max_rows)
    let cell_limit = try budget(max_cells)
    let byte_limit = min(try budget(max_bytes), OUTPUT_LIMIT)
    if padding < 0:
        return error(TableError.InvalidInput)

    let count = rows.length()
    if count > row_limit:
        return error(TableError.LimitExceeded)

    var columns = 0
    if count > 0:
        columns = rows[0].length()
    if alignments.length() > 0 and alignments.length() != columns:
        return error(TableError.InvalidInput)
    if columns > 0 and count > cell_limit / columns:
        return error(TableError.LimitExceeded)
    if columns > 1 and padding > byte_limit / (columns - 1):
        return error(TableError.LimitExceeded)

    let gap = max(columns - 1, 0) * padding
    if count > 0 and gap > byte_limit / count:
        return error(TableError.LimitExceeded)

    var bytes = try add(max(count - 1, 0), gap * count, byte_limit)

    for row in rows:
        if row.length() != columns:
            return error(TableError.InvalidData)

        for cell in row:
            bytes = try add(bytes, cell.byte_length(), byte_limit)

    var widths = List[Int]()
    for _unused in 0..columns:
        widths.append(0)
    for row in rows:
        for col in 0..columns:
            widths[col] = max(widths[col], try msstd_table_cell_width(row[col]))

    for row in rows:
        for col in 0..columns:
            let spare = widths[col] - (try msstd_table_cell_width(row[col]))
            var fill = spare
            if col + 1 == columns:
                fill = leading(alignments, col, spare)
            bytes = try add(bytes, fill, byte_limit)

    var out = StringBuilder()

    for index in 0..count:
        if index > 0:
            out.append("\n")

        let row = rows[index]

        for col in 0..columns:
            if col > 0:
                out.append(spaces(padding))

            let spare = widths[col] - (try msstd_table_cell_width(row[col]))
            let left = leading(alignments, col, spare)
            out.append(spaces(left))
            out.append(row[col])
            if col + 1 < columns:
                out.append(spaces(spare - left))

    return ok(out.build())

# The largest table output: the native string byte limit.
let OUTPUT_LIMIT = 1073741824

# A budget argument: absent is unlimited, negative is invalid.
fn budget(limit: Int?) Int!TableError:
    if let n = limit:
        if n < 0:
            return error(TableError.InvalidInput)

        return ok(n)

    return ok(9223372036854775807)

# Adds `n` bytes to `total`, failing when the sum passes `limit` (`total` never exceeds `limit` on success).
fn add(total: Int, n: Int, limit: Int) Int!TableError:
    if n > limit or total > limit - n:
        return error(TableError.LimitExceeded)

    return ok(total + n)

# Spaces placed before a cell: all spare for Right, half for Center, none for Left or no alignment.
fn leading(alignments: List[Alignment], col: Int, spare: Int) Int:
    if alignments.length() == 0:
        return 0

    match alignments[col]:
        Left: return 0
        Right: return spare
        Center: return spare / 2

fn spaces(count: Int) String:
    return " ".repeat(count, none).get("")

impl Error for TableError:
    # Returns a table-prefixed diagnostic for the validation or budget failure.
    fn message() String:
        match self:
            InvalidInput: return "table: invalid input"
            InvalidData: return "table: invalid data"
            LimitExceeded: return "table: limit exceeded"
