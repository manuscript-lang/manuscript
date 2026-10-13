# CSV to aligned table

Standard input is CSV text (ASCII only). Render it as an aligned text table.

## Parsing

- Lines that are completely empty (zero characters) are skipped. Every other line is a row; the first row is
  the header.
- A row is split into fields at commas. A field that **starts with `"`** is *quoted*: it runs to the first
  closing `"` that is not followed by another `"`, and `""` inside it stands for one `"`. The closing quote is
  followed by a comma or the end of the line, and a quoted field may contain commas. The surrounding quotes
  are not part of the value. A field that does not start with `"` runs to the next comma and is kept
  verbatim (spaces included, quotes inside it are ordinary characters). A trailing comma produces a final
  empty field.
- The number of columns is the number of fields in the header. A data row with fewer fields is padded with
  empty fields; extra fields beyond the header's count are dropped.

## Layout

- A column is *numeric* if there is at least one data row and every data cell in the column (after padding
  and dropping) matches `-?[0-9]+` (an optional minus sign, then one or more digits). Other columns are
  *text* columns.
- The width of a column is the length of its longest cell, header included.
- Text cells are left-aligned and padded with spaces on the right; numeric cells (and the header cell of a
  numeric column) are right-aligned and padded on the left.
- Cells of a row are joined with `" | "`. Then remove trailing spaces from the end of the line.
- Output: the header row, then a separator line made of `-` repeated to each column's width, joined with
  `"-+-"`, then the data rows.

No input (no rows) prints nothing.

Example input:

    name,qty,note
    apple,3,"red, sweet"
    kiwi,12,
    fig,-5,"say ""hi"""

Output:

    name  | qty | note
    ------+-----+------------
    apple |   3 | red, sweet
    kiwi  |  12 |
    fig   |  -5 | say "hi"
