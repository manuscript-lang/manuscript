# Maze shortest path

The input is a grid, one row per line. Characters: `#` wall, `.` open floor, `S` the start cell, `E` the
end cell. `S` and `E` are walkable. Trailing empty lines at the end of the input are ignored; an empty line
anywhere before the last non-empty line is a row of width 0.

Print the minimum number of moves from `S` to `E`, moving one cell at a time up, down, left or right (no
diagonals) through non-wall cells, or `no path` if `E` cannot be reached. `S` and `E` are
different cells, so the answer is at least 1 when a path exists.

Validation comes first. The following checks are made in order and the first failure is the only output:

1. Any character other than `#`, `.`, `S`, `E`: `error: bad character at R,C` where `R` is the 1-based row
   and `C` the 1-based column (counted in characters) of the first such character in reading order.
2. Rows of different widths: `error: ragged grid`
3. No `S`: `error: no start`; more than one `S`: `error: multiple starts`
4. No `E`: `error: no end`; more than one `E`: `error: multiple ends`

An input with no rows at all is `error: no start`.

Example input:

    S.#.....
    .##.###.
    ....#...
    .####.#.
    ......#E

Output:

    15
