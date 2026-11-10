import expect_equal from "@std/test/test.ms"

type Cell:
	value: Int

fn at(var events: List[Int], n: Int) Int:
	events.append(n)
	return 0

fn arg(var events: List[Int], n: Int) Int:
	events.append(n)
	return 9

test "nested field assignment evaluates indices left to right":
	var grid = [[Cell(0)]]
	var events: List[Int] = []
	grid[at(var events, 1)][at(var events, 2)].value = 9
	try expect_equal(grid[0][0].value, 9)
	try expect_equal(events, [1, 2])

test "three nested indices run in written order":
	var cube = [[[Cell(0)]]]
	var events: List[Int] = []
	cube[at(var events, 1)][at(var events, 2)][at(var events, 3)].value = 5
	try expect_equal(cube[0][0][0].value, 5)
	try expect_equal(events, [1, 2, 3])

test "an indexed receiver runs before the arguments of a changing method":
	var rows = [[0]]
	var events: List[Int] = []
	rows[at(var events, 1)].set(0, arg(var events, 2))
	try expect_equal(rows[0][0], 9)
	try expect_equal(events, [1, 2])

fn bump(var x: Int) Unit:
	x += 1

fn bump_both(var a: Int, var b: Int) Unit:
	a += 1
	b += 10

fn index(var calls: Int) Int:
	calls += 1
	return 0

test "a var element argument evaluates its index once":
	var calls = 0
	var xs = [1]
	bump(var xs[index(var calls)])
	try expect_equal(calls, 1)
	try expect_equal(xs, [2])

test "several var element arguments evaluate each index once":
	var calls = 0
	var xs = [1, 2]
	var ys = [[3]]
	bump_both(var xs[index(var calls)], var ys[index(var calls)][index(var calls)])
	try expect_equal(calls, 3)
	try expect_equal(xs, [2, 2])
	try expect_equal(ys, [[13]])

test "a var field of an indexed element evaluates its index once":
	var events: List[Int] = []
	var cells = [Cell(1)]
	bump(var cells[at(var events, 7)].value)
	try expect_equal(events, [7])
	try expect_equal(cells[0].value, 2)
