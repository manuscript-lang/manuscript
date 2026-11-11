// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type P:
	n: Int
	name: String

test "for_each changes records in place":
	var xs = [P(1, "a"), P(2, "b")]
	xs.for_each(fn var p: p.n *= 10)
	expect_equal(xs[0].n, 10)?
	expect_equal(xs[1].n, 20)?

test "for_each changes scalars and strings":
	var ns = [1, 2, 3]
	ns.for_each(fn var n: n *= 2)
	expect_equal(ns, [2, 4, 6])?

	var ss = ["a", "b"]
	ss.for_each(fn var s: s += "!")
	expect_equal(ss, ["a!", "b!"])?

test "for_each on an empty list does nothing":
	var xs: List[Int] = []
	xs.for_each(fn var n: n = 1)
	expect_equal(xs.length(), 0)?

test "a reading callback works on a let list":
	xs := [1, 2, 3]
	var total = 0
	xs.for_each(fn n: total += n)
	expect_equal(total, 6)?

fn bump(var p: P) Unit:
	p.n += 1

test "a named function with a var parameter":
	var xs = [P(1, "a"), P(5, "b")]
	xs.for_each(bump)
	expect_equal(xs[0].n, 2)?
	expect_equal(xs[1].n, 6)?

test "Map.for_each changes values in place":
	var m: Map[String, Int] = {"a": 1, "b": 2}
	m.for_each(fn k, var v: v += k.length() * 10)
	expect_equal(m["a"], 11)?
	expect_equal(m["b"], 12)?

test "Map.for_each changes record values":
	var m: Map[String, P] = {"a": P(1, "x")}
	m.for_each(fn k, var p: p.n += 5)
	expect_equal(m["a"].n, 6)?

test "Map.for_each reads on a let map":
	m: Map[String, Int] := {"a": 1, "b": 2}
	var total = 0
	m.for_each(fn k, v: total += v)
	expect_equal(total, 3)?
