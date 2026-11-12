// conform: tags=closures,lists,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn weighted(xs: List[Int], k: Int) Int:
	return xs.filter(fn x: x % 3 == 0).map(fn x: x * k).sum()

test "filter, map and sum agree with the stages run one at a time":
	xs := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	expect_equal(weighted(xs, 2), 36)?
	expect_equal(xs.filter(fn x: x > 4).sum(), 35)?
	expect_equal(xs.map(fn x: x * x).sum(), 285)?
	expect_equal(xs.map(fn x: x + 1).filter(fn x: x % 2 == 0).map(fn x: x * 10).sum(), 300)?

test "chains that build a list":
	xs := [5, 1, 4, 2, 3]
	expect_equal(xs.filter(fn x: x > 1).map(fn x: x * 2), [10, 8, 4, 6])?
	expect_equal(xs.map(fn x: x - 1).map(fn x: x * x), [16, 0, 9, 1, 4])?
	expect_equal(xs.filter(fn x: x > 1).filter(fn x: x < 5), [4, 2, 3])?
	expect_equal(xs.map(fn x: x > 2).filter(fn b: b).map(fn b: if b: 1 else: 0), [1, 1, 1])?

test "empty and fully filtered inputs":
	none: List[Int] := []
	expect_equal(none.filter(fn x: x > 0).map(fn x: x + 1).sum(), 0)?
	expect_equal([1, 2].filter(fn x: x > 5).map(fn x: x + 1), [])?
	expect_equal([1, 2].filter(fn x: x > 5).sum(), 0)?

test "floats and captured values":
	fs := [1.5, 2.5, 4.0]
	scale := 2.0
	expect_equal(fs.filter(fn x: x > 2.0).map(fn x: x * scale).sum(), 13.0)?
	table := [10, 20, 30]
	expect_equal([0, 2, 1].map(fn i: table[i]).sum(), 60)?

test "a lambda that calls a function runs the stages one at a time":
	xs := [1, 2, 3, 4, 5]
	expect_equal(xs.filter(fn x: x.min(3) == 3).map(fn x: x * 2).sum(), 24)?
	expect_equal(xs.map(fn x: x * 2).filter(fn x: x.max(4) == x), [4, 6, 8, 10])?
