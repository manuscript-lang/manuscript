import max from "@std/math/math.ms"
import StringBuilder from "@std/string.ms"

// Horizontal placement of a cell within its column's measured display width.
// Example: `Table(columns: [Align.Left, Align.Right])`.
export enum Align:
    Left  // Places unused column space after the cell.
    Right  // Places unused column space before the cell.
    Center  // Splits unused space, putting an odd extra space after the cell.

fn table_invalid(message: String) Error:
    return Error("table: {message}", kind: "EBADMSG")

/*
Aligned text columns for terminal output. `columns` gives one alignment per column; `padding` is the
number of spaces between columns (default 2, negative counts as 0) and `indent` the spaces before each
non-blank line. Rows are added one at a time and rendered as LF-separated lines with no final LF.

```manuscript
import Align, Table from "@std/cli/table.ms"

fn render() String!:
    var table = Table(columns: [Align.Left, Align.Right])
    try table.add(["tea", "2"])
    try table.add(["coffee", "30"])
    return table.render()
```

Unicode widths use `String.display_width`: cell bytes stay intact and widths are estimates, not a promise
for every font or terminal. Cells containing controls (tabs, CR/LF, ESC, C1, U+2028, U+2029) are rejected by
`add`, never expanded or interpreted. Trailing columns whose cells are empty are omitted, so no line ends in
added padding; a table without rows renders as "".
*/
export type Table:
    columns: List[Align]
    padding: Int = 2
    indent: Int = 0
    // Internal state: the added rows.
    rows: List[List[String]] = []
    // Internal state: the display width of every cell in `rows`.
    cell_widths: List[List[Int]] = []
    // Internal state: the widest cell of each column.
    widths: List[Int] = []

impl Table:
    // Appends a row of exactly one cell per column. A wrong cell count or a cell with controls returns EBADMSG.
    var fn add(row: List[String]) Unit!:
        let count = self.columns.length()
        if row.length() != count:
            return error(
                table_invalid(
                    "row has {row.length()} cells, expected {count}"
                )
            )

        var measured = List[Int]()
        for cell in row:
            measured.append(try cell.display_width())
        if self.widths.is_empty():
            for _unused in 0..count:
                self.widths.append(0)
        for col in 0..count:
            self.widths[col] = max(self.widths[col], measured[col])
        self.cell_widths.append(measured)
        self.rows.append(row)
        return ok(unit)

    // Lays out the rows added so far; the table is unchanged and can keep growing.
    fn render() String:
        var out = StringBuilder()
        let lead = "".pad_start(self.indent, " ")
        let gap = "".pad_start(self.padding, " ")

        for index in 0..self.rows.length():
            if index > 0:
                out.append("\n")

            let row = self.rows[index]
            var last = row.length() - 1
            while last >= 0 and row[last].is_empty():
                last -= 1
            if last < 0:
                continue

            out.append(lead)

            for col in 0..last + 1:
                if col > 0:
                    out.append(gap)

                let spare = self.widths[col] - self.cell_widths[index][col]
                let before = self.before(col, spare)
                out.append("".pad_start(before, " "))
                out.append(row[col])
                if col < last:
                    out.append("".pad_start(spare - before, " "))

        return out.build()

    // Spaces placed before a cell: all spare for Right, half for Center, none for Left.
    fn before(col: Int, spare: Int) Int:
        match self.columns[col]:
            Left: return 0
            Right: return spare
            Center: return spare / 2
