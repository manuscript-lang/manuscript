import Alignment from "@std/io/table.ms"

export extern fn msstd_table_format(
    rows: List[List[String]],
    alignments: List[Alignment],
    padding: Int,
    max_rows: Int?,
    max_cells: Int?,
    max_bytes: Int?
) String!
