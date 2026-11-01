import expect_equal from "@std/test/test.ms"

test "integer comparison sorts accept empty and singleton lists":
    let empty = List[Int]()
    try expect_equal(empty.sorted(fn a, b: a.compare(b)), List[Int]())
    try expect_equal(empty.sorted(fn a, b: b.compare(a)), List[Int]())
    try expect_equal(empty.sorted(), List[Int]())
    try expect_equal([7].sorted(fn a, b: a.compare(b)), [7])
    try expect_equal([7].sorted(fn a, b: b.compare(a)), [7])

test "integer comparison sorts keep full-width ordering":
    let values = [9223372036854775807, 0, -9223372036854775807 - 1, 0]
    try expect_equal(
        values.sorted(fn a, b: a.compare(b)),
        [-9223372036854775807 - 1, 0, 0, 9223372036854775807]
    )
    try expect_equal(
        values.sorted(fn a, b: b.compare(a)),
        [9223372036854775807, 0, 0, -9223372036854775807 - 1]
    )
