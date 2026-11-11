import expect_true from "@std/test/test.ms"

type Point:
	x: Int
	y: Int

type Tagged:
	id: Int32
	ok: Bool
	n: Int

type Named:
	name: String
	n: Int

type Folded:
	n: Int

impl Hashable for Folded:
	fn hash() Int:
		return 0

impl Equal for Folded:
	fn equals(other: Folded) Bool:
		return true

test "plain record keys":
	var m = Map[Point, Int]()
	for i in 0..50:
		m.add(Point(x: i, y: i * 2), i)
	expect_true(m.length() == 50)?
	expect_true(m.get_or(Point(y: 20, x: 10), -1) == 10)?
	expect_true(m.get_or(Point(x: 10, y: 21), -1) == -1)?
	m.add(Point(x: 3, y: 6), 99)
	expect_true(m.length() == 50 and m.get_or(Point(x: 3, y: 6), -1) == 99)?

test "padded and mixed width keys":
	var m = Map[Tagged, Int]()
	m.add(Tagged(id: 1, ok: true, n: 5), 1)
	m.add(Tagged(id: 1, ok: false, n: 5), 2)
	expect_true(m.get_or(Tagged(n: 5, ok: true, id: 1), 0) == 1)?
	expect_true(m.get_or(Tagged(n: 5, ok: false, id: 1), 0) == 2)?
	expect_true(m.get_or(Tagged(n: 6, ok: false, id: 1), 0) == 0)?

test "record keys holding strings use the general path":
	var m = Map[Named, Int]()
	m.add(Named(name: "a", n: 1), 1)
	m.add(Named(name: "b", n: 1), 2)
	expect_true(m.get_or(Named(name: "b", n: 1), 0) == 2)?
	expect_true(m.get_or(Named(name: "c", n: 1), 0) == 0)?

test "user equal and hash keys":
	var m = Map[Folded, Int]()
	m.add(Folded(n: 1), 1)
	m.add(Folded(n: 2), 2)
	expect_true(m.length() == 1)?
	expect_true(m.get_or(Folded(n: 9), 0) == 2)?
