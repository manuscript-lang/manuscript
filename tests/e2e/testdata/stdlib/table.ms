import Alignment, format from "@std/io/table.ms"
import expect_equal from "@std/test/test.ms"

test "table aligns columns with no added trailing spaces or final LF":
    let rows = [["name", "count"], ["tea", "2"], ["coffee", "30"]]
    try expect_equal(
        (try format(rows, [Alignment.Left, Alignment.Right])),
        "name    count\ntea         2\ncoffee     30"
    )
    try expect_equal(
        (try format(rows, padding: 1)), "name   count\ntea    2\ncoffee 30"
    )

    let centered = [["abc", "abcd"], ["x", "y"]]
    try expect_equal(
        (
            try format(
                centered, [Alignment.Center, Alignment.Center], padding: 1
            )
        ),
        "abc abcd\n x   y"
    )

test "table keeps combining wide and emoji sequences intact":
    let rows = [["é", "a"], ["界", "b"], ["👩‍💻", "c"], ["·", "d"]]
    try expect_equal((try format(rows, padding: 1)), "é  a\n界 b\n👩‍💻 c\n·  d")
    try expect_equal(rows[0][0], "é")

test "table supports empty inputs and zero cell rows":
    let empty: List[List[String]] = []
    try expect_equal((try format(empty, max_rows: 0, max_cells: 0, max_bytes: 0)), "")
    try expect_equal((try format([[]], max_cells: 0, max_bytes: 0)), "")
    try expect_equal((try format([[], []], max_cells: 0, max_bytes: 1)), "\n")
    try expect_equal((try format([[""]], max_bytes: 0)), "")

test "table returns typed errors for malformed cells rows and options":
    let invalid: String! = error(
        Error("table: invalid input", kind: ErrorCategory.InvalidInput)
    )
    let malformed: String! = error(
        Error("table: invalid data", kind: ErrorCategory.InvalidData)
    )
    let rows = [["a", "b"]]
    try expect_equal(format(rows, padding: -1), invalid)
    try expect_equal(format(rows, max_rows: -1), invalid)
    try expect_equal(format(rows, max_cells: -1), invalid)
    try expect_equal(format(rows, max_bytes: -1), invalid)
    try expect_equal(format(rows, [Alignment.Left]), invalid)
    try expect_equal(format([], [Alignment.Right]), invalid)
    try expect_equal(format([["a"], []]), malformed)
    try expect_equal(format([[], ["a"]]), malformed)
    for cell in [
        "tab\there", "line\nbreak", "return\r", "\u{0}", "\u{1b}[31mred", "\u{85}",
        "\u{2028}", "\u{2029}"
    ]:
        try expect_equal(format([[cell.clone()]]), malformed)

test "table applies exact optional budgets to UTF8 and generated padding":
    let rows = [["界", "x"], ["a", "yz"]]
    let expected = "界   x\n a  yz"
    let alignments = [Alignment.Right, Alignment.Right]
    let limited: String! = error(
        Error("table: limit exceeded", kind: ErrorCategory.LimitExceeded)
    )
    try expect_equal(
        (
            try format(
                rows, alignments, max_rows: 2, max_cells: 4,
                max_bytes: expected.byte_length()
            )
        ),
        expected
    )
    try expect_equal(
        (
            try format(
                rows, alignments, max_rows: none, max_cells: none, max_bytes: none
            )
        ),
        expected
    )
    try expect_equal(format(rows, alignments, max_rows: 1), limited)
    try expect_equal(format(rows, alignments, max_cells: 3), limited)
    try expect_equal(
        format(rows, alignments, max_bytes: expected.byte_length() - 1), limited
    )
    try expect_equal(format(rows, padding: 9223372036854775807), limited)
    try expect_equal(format([["a"]], max_rows: 0), limited)
    try expect_equal(format([["a"]], max_cells: 0), limited)
    try expect_equal(format([["a"]], max_bytes: 0), limited)
    try expect_equal(format([[], []], max_bytes: 0), limited)

test "table errors describe the table domain":
    try expect_equal(
        Error("table: invalid input", kind: ErrorCategory.InvalidInput).message,
        "table: invalid input"
    )
    try expect_equal(
        Error("table: invalid data", kind: ErrorCategory.InvalidData).message,
        "table: invalid data"
    )
    try expect_equal(
        Error(
            "table: limit exceeded", kind: ErrorCategory.LimitExceeded
        ).message,
        "table: limit exceeded"
    )

test "table formatting borrows retained rows across repeated calls":
    var rows = [["name", "count"], ["tea", "2"]]
    let alignments = [Alignment.Left, Alignment.Right]
    let first = try format(rows, alignments)
    let second = try format(rows, alignments)
    try expect_equal(first, "name  count\ntea       2")
    try expect_equal(second, first)
    try expect_equal(rows, [["name", "count"], ["tea", "2"]])
    try expect_equal(rows[1][0], "tea")
    rows.append(["coffee", "30"])
    try expect_equal(rows.length(), 3)
    try expect_equal(rows[2][0], "coffee")
