import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import Memo from "@std/collections/memo.ms"

fn square(n: Int) Int:
    return n * n

test "memo returns computed results":
    var squares = Memo[Int, Int](compute: square)
    try expect_equal(squares.get(4), 16)
    try expect_equal(squares.get(4), 16)
    try expect_equal(squares.get(5), 25)
    try expect_equal(squares.length(), 2)
    try expect_true(squares.contains(5))
    try expect_false(squares.contains(6))

test "memo keeps one result per argument and clear forgets them":
    var tracked = Memo[Int, Int](compute: fn n: n + 1)
    try expect_equal(tracked.get(1), 2)
    try expect_equal(tracked.get(1), 2)
    try expect_equal(tracked.get(2), 3)
    try expect_equal(tracked.length(), 2)
    tracked.clear()
    try expect_equal(tracked.length(), 0)
    try expect_equal(tracked.get(1), 2)
