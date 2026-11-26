// conform: tags=lists,mutation
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A constant list of scalars is read from static data. A use that keeps or changes the
// list gets its own copy, so the constant never changes.
table := [3, 1, 4, 1, 5, 9, 2, 6]
scale := [1.5, -2.5]
flags := [true, false]
small := [-1, 2]

type Box {
	items List[Int]
}

fn give() List[Int] {
	return table.clone()
}

fn bump(var l List[Int]) Void {
	l[0] = 99
}

fn total(l List[Int]) Int {
	var s = 0
	for x in l {
		s += x
	}
	return s
}

test "reads see the constant" {
	table[2] | expect_equal(4)?
	table.length() | expect_equal(8)?
	total(table) | expect_equal(31)?
	scale[1] | expect_equal(-2.5)?
	flags[0] | expect_equal(true)?
	small[0] | expect_equal(-1)?
}

test "a copy is changed without changing the constant" {
	var a = give()
	a[0] = 7
	a.append(8)
	a | expect_equal([7, 1, 4, 1, 5, 9, 2, 6, 8])?

	var b = Box(items: table.clone())
	b.items[1] = 50
	b.items[1] | expect_equal(50)?

	var c = table.clone()
	bump(c)
	c[0] | expect_equal(99)?

	var d = [table.clone(), table.clone()]
	d[1][0] = 0
	d[0][0] | expect_equal(3)?
	table | expect_equal([3, 1, 4, 1, 5, 9, 2, 6])?
	give() | expect_equal([3, 1, 4, 1, 5, 9, 2, 6])?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
