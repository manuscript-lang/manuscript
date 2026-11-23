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
	expect_equal(
		xs.map(fn x: x + 1).filter(fn x: x % 2 == 0).map(fn x: x * 10).sum(),
		300,
	)?

test "chains that build a list":
	xs := [5, 1, 4, 2, 3]
	expect_equal(xs.filter(fn x: x > 1).map(fn x: x * 2), [10, 8, 4, 6])?
	expect_equal(xs.map(fn x: x - 1).map(fn x: x * x), [16, 0, 9, 1, 4])?
	expect_equal(xs.filter(fn x: x > 1).filter(fn x: x < 5), [4, 2, 3])?
	expect_equal(
		xs.map(fn x: x > 2).filter(fn b: b).map(fn b: if b: 1 else: 0),
		[1, 1, 1],
	)?

test "empty and fully filtered inputs":
	null: List[Int] := []
	expect_equal(null.filter(fn x: x > 0).map(fn x: x + 1).sum(), 0)?
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

fn odd(x: Int) Bool:
	return x % 2 == 1

fn square(x: Int) Int:
	return x * x

fn cube(x: Int) Int:
	return square(x) * x

fn clamp(x: Int) Int:
	var out = x
	if out > 4: out = 4
	return out

test "named functions fuse like lambdas, including functions that call functions":
	xs := [1, 2, 3, 4, 5]
	expect_equal(xs.filter(odd).map(square).sum(), 35)?
	expect_equal(xs.map(cube).filter(odd).sum(), 153)?
	expect_equal(xs.map(clamp).map(square).sum(), 46)?
	expect_equal(xs.filter(odd).map(fn x: cube(x) + 1), [2, 28, 126])?

test "zipped numbers feed a chain without building the pairs":
	a := [1, 2, 3, 4]
	b := [10, 20, 30]
	expect_equal(a.zip(b).map(fn p: p.first * p.second).sum(), 140)?
	expect_equal(b.zip(a).map(fn p: p.first - p.second).sum(), 54)?
	expect_equal(a.zip(a).map(fn p: p.first * p.second).sum(), 30)?
	expect_equal(
		a.zip(b).map(fn p: p.first + p.second).filter(fn v: v > 15).map(
			square
		).sum(),
		1573,
	)?

	null: List[Int] := []
	expect_equal(null.zip(b).map(fn p: p.first).sum(), 0)?
	expect_equal(a.zip(null).map(fn p: p.first).sum(), 0)?
	expect_equal(a.zip(b).map(fn p: p.first + p.second).map(square), [121, 484, 1089])?

type Order:
	status: String
	total: Int
	tags: List[String]

test "chains over records and strings read each element in place":
	orders := [
		Order("placed", 5, ["a"]),
		Order("shipped", 7, []),
		Order("placed", 11, ["b", "c"]),
	]
	wanted := "placed"
	expect_equal(orders.filter(fn o: o.status == "placed").map(fn o: o.total).sum(), 16)?
	expect_equal(orders.filter(fn o: o.status == wanted).map(fn o: o.total), [5, 11])?
	expect_equal(orders.map(fn o: o.total).filter(fn t: t > 5).sum(), 18)?

	words := ["x", "yy", "zzz"]
	expect_equal(words.filter(fn w: w != "yy").map(fn w: w.length()).sum(), 4)?
	expect_equal(words.map(fn w: w.length()).filter(fn n: n > 1), [2, 3])?
	expect_equal(orders.filter(fn o: o.status == "none").map(fn o: o.total).sum(), 0)?
	expect_equal(orders.filter(fn o: o.status == "placed").length(), 2)?
	expect_equal(
		orders.filter(fn o: o.status == "placed").filter(fn o: o.total > 6).map(
			fn o: o.total
		),
		[11],
	)?
