import expect_equal from "@std/test.ms"

fn bump(var xs: List[Int], i: Int) Bool:
    if var n = xs[i]?:
        n += 1
        return true

    return false

test "list probe":
    var xs = [1, 2]
    try expect_equal(bump(var xs, 1), true)
    try expect_equal(bump(var xs, 2), false)
    try expect_equal(bump(var xs, -1), false)
