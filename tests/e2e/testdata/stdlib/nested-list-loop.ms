import expect_equal from "@std/test/test.ms"

// A loop over `rows[i]` or `rows.get(i)` walks the inner list in place while `rows` is unchanged.
fn total_indexed(rows: List[List[Int]], slot: Int) Int:
    var total = 0
    for value in rows[slot]:
        total += value
    return total

fn total_get(rows: List[List[Int]], slot: Int) Int:
    var total = 0
    for value in rows.get(slot):
        total += value
    return total

fn lengths(rows: List[List[String]]) Int:
    var total = 0
    for word in rows[1]:
        total += word.length()
    return total

test "a loop borrows an inner list reached by index or get":
    let rows = [[1, 2], [3, 4, 5]]
    try expect_equal(total_indexed(rows, 1), 12)
    try expect_equal(total_get(rows, 0), 3)
    try expect_equal(lengths([["a"], ["bb", "ccc"]]), 5)
