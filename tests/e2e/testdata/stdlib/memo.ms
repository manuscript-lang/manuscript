import (
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
	Memo, Memo2, Memo3 from "@std/collections/memo.ms",
)

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

test "memo2 keeps one result per argument pair":
	var grid = Memo2[Int, String, Int](compute: fn n, s: n + s.length())
	try expect_equal(grid.get(1, "ab"), 3)
	try expect_equal(grid.get(1, "ab"), 3)
	try expect_equal(grid.get(1, "abc"), 4)
	try expect_equal(grid.get(2, "ab"), 4)
	try expect_equal(grid.length(), 3)
	try expect_true(grid.contains(2, "ab"))
	try expect_false(grid.contains(2, "abc"))
	grid.clear()
	try expect_equal(grid.length(), 0)

test "memo3 keeps one result per argument triple":
	var cube = Memo3[Int, Int, Int, Int](compute: fn a, b, c: a * b * c)
	try expect_equal(cube.get(2, 3, 4), 24)
	try expect_equal(cube.get(2, 3, 4), 24)
	try expect_equal(cube.get(4, 3, 2), 24)
	try expect_equal(cube.length(), 2)
	try expect_false(cube.contains(1, 1, 1))
