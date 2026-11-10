import expect_equal from "@std/test/test.ms"

fn row[T](rows: List[List[T]], at: Int) List[T]:
    return rows[at]

fn first_row(rows: List[List[Int]]) List[Int]:
    return rows[0]

type Grid:
    rows: List[List[Int]]

impl Grid:
    fn first() List[Int]:
        return self.rows[0]

fn total(rows: List[List[Int]]) Int:
    var sum = row(rows, 0).sum()
    return sum

fn fresh_row() List[Int]:
    return [4, 5, 6]

test "borrowed helper iterables keep scalar and string elements in place":
    let rows = [[1, 2], [3, 4]]
    var sum = first_row(rows).sum()
    try expect_equal(sum, 3)
    try expect_equal(total(rows), 3)
    sum = 0
    for value in rows[0]:
        sum += value
    try expect_equal(sum, 3)

    let first = row(rows, 0)
    sum = 0
    for value in first:
        sum += value
    try expect_equal(sum, 3)
    try expect_equal(rows[0], [1, 2])

    let words = [["a", "bb"]]
    var length = 0
    for word in row(words, 0):
        length += word.length()
    try expect_equal(length, 3)
    try expect_equal(words[0], ["a", "bb"])

test "borrowed receiver iterable handles break and continue":
    let grid = Grid([[1, 2, 3, 4]])
    var sum = 0

    for value in grid.first():
        if value == 2: continue

        sum += value
        if value == 3: break

    try expect_equal(sum, 4)
    try expect_equal(grid.rows[0], [1, 2, 3, 4])

test "fresh results and temporary owners remain owned":
    var sum = fresh_row().sum()
    try expect_equal(sum, 15)
    sum = 0
    for value in row([[7, 8]], 0):
        sum += value
    try expect_equal(sum, 15)
