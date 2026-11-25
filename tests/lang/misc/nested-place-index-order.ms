// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Cell {
	value Int
}

fn at(var events List[Int], n Int) Int {
	events.append(n)
	return 0
}

fn arg(var events List[Int], n Int) Int {
	events.append(n)
	return 9
}

test "nested field assignment evaluates indices left to right" {
	var grid = [[Cell(0)]]
	var events List[Int] = []
	grid[at(events, 1)][at(events, 2)].value = 9
	expect_equal(grid[0][0].value, 9)?
	expect_equal(events, [1, 2])?
}

test "three nested indices run in written order" {
	var cube = [[[Cell(0)]]]
	var events List[Int] = []
	cube[at(events, 1)][at(events, 2)][at(events, 3)].value = 5
	expect_equal(cube[0][0][0].value, 5)?
	expect_equal(events, [1, 2, 3])?
}

test "an indexed receiver runs before the arguments of a changing method" {
	var rows = [[0]]
	var events List[Int] = []
	rows[at(events, 1)].set(0, arg(events, 2))
	expect_equal(rows[0][0], 9)?
	expect_equal(events, [1, 2])?
}

fn bump(var x Int) Void {
	x += 1
}

fn bump_both(var a Int, var b Int) Void {
	a += 1
	b += 10
}

fn index(var calls Int) Int {
	calls += 1
	return 0
}

test "a var element argument evaluates its index once" {
	var calls = 0
	var xs = [1]
	bump(xs[index(calls)])
	expect_equal(calls, 1)?
	expect_equal(xs, [2])?
}

test "several var element arguments evaluate each index once" {
	var calls = 0
	var xs = [1, 2]
	var ys = [[3]]
	bump_both(xs[index(calls)], ys[index(calls)][index(calls)])
	expect_equal(calls, 3)?
	expect_equal(xs, [2, 2])?
	expect_equal(ys, [[13]])?
}

test "a var field of an indexed element evaluates its index once" {
	var events List[Int] = []
	var cells = [Cell(1)]
	bump(cells[at(events, 7)].value)
	expect_equal(events, [7])?
	expect_equal(cells[0].value, 2)?
}
// expect-exit: 0
// expect-tests: passed=6 failed=0
