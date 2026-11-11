// conform: tags=optional,stdlib-deque,stdlib-testing,testing,tier-stdlib
// conform: phase=test
import (
	Deque from "@std/collections/deque.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "both ends push and pop":
	var d = Deque[Int]()
	expect_true(d.is_empty())?
	expect_equal(d.pop_front(), none)?
	expect_equal(d.pop_back(), none)?
	d.push_back(2)
	d.push_back(3)
	d.push_front(1)
	d.push_front(0)
	expect_equal(d.to_list(), [0, 1, 2, 3])?
	expect_equal(d.front(), 0)?
	expect_equal(d.back(), 3)?
	expect_equal(d.pop_front(), 0)?
	expect_equal(d.pop_back(), 3)?
	expect_equal(d.length(), 2)?

test "indexed reads follow the front":
	var d = Deque[String]()
	for name in ["b", "c", "d"]:
		d.push_back(name)
	d.push_front("a")
	expect_equal(d.at(0), "a")?
	expect_equal(d.at(3), "d")?
	expect_equal(d.at(4), none)?
	expect_equal(d.at(-1), none)?

test "wraps around and grows past the first buffer":
	var d = Deque[Int]()
	var expected: List[Int] = []

	for i in 0..100:
		d.push_back(i)
		d.push_front(-i)
		expected.append(i)
		expected.prepend(-i)

		if i % 3 == 0:
			expect_equal(d.pop_front(), expected.get(0))?
			expected = expected.drop(1)
			expect_equal(d.pop_back(), expected.pop().get())?

	expect_equal(d.to_list(), expected)?

test "a copy is independent and clear empties":
	var d = Deque[Int]()
	d.push_back(1)

	var e = d.clone()
	e.push_back(2)
	expect_equal(d.to_list(), [1])?
	expect_equal(e.to_list(), [1, 2])?
	e.clear()
	expect_true(e.is_empty())?
	e.push_front(7)
	expect_equal(e.to_list(), [7])?

test "optional elements keep none distinct from absent":
	var d = Deque[Int?]()
	d.push_back(none)
	expect_equal(d.length(), 1)?

	present_none: Int? := none
	expect_equal(d.pop_front(), present_none)?
	expect_equal(d.pop_front(), none)?
