import msstd_table_format from "@std/internal/table.ms"

# Horizontal placement of a cell within its column's measured display width.
# Example: `format([["name", "count"], ["tea", "2"]], [Alignment.Left, Alignment.Right])`.
export type Alignment:
    # Places unused column space after the cell.
    case Left
    # Places unused column space before the cell.
    case Right
    # Splits unused space, putting an odd extra space after the cell.
    case Center

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
) String!:
    return msstd_table_format(rows, alignments, padding, max_rows, max_cells, max_bytes)
