import TableError from "@std/io/table.ms"

# Display width of one cell (ambiguous characters narrow); controls, U+2028 and U+2029 are InvalidData.
export extern fn msstd_table_cell_width(text: String) Int!TableError
