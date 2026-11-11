import (
	Deque from "@std/collections/deque.ms",
	expect_equal, expect_false, expect_fault, expect_true from "@std/test/test.ms",
)

type Person:
	name: String
	age: Int

test "retain keeps matching elements in order":
	var xs = [1, 2, 3, 4, 5, 6]
	xs.retain(fn x: x % 2 == 0)
	expect_equal(xs, [2, 4, 6])?

	var words = ["a", "bb", "c", "dd"]
	words.retain(fn w: w.length() == 2)
	expect_equal(words, ["bb", "dd"])?

	var none_left = [1, 3]
	none_left.retain(fn x: x > 5)
	expect_equal(none_left, List[Int]())?

	var empty = List[Int]()
	empty.retain(fn x: true)
	expect_equal(empty, List[Int]())?

test "compact collapses runs only":
	var xs = [1, 1, 2, 2, 2, 1, 3, 3]
	xs.compact()
	expect_equal(xs, [1, 2, 1, 3])?

	var one = [7]
	one.compact()
	expect_equal(one, [7])?

	var words = ["a", "A", "b"]
	words.compact_by(fn a, b: a.lower() == b.lower())
	expect_equal(words, ["a", "b"])?

test "rotate wraps in both directions":
	var xs = [1, 2, 3, 4, 5]
	xs.rotate(2)
	expect_equal(xs, [3, 4, 5, 1, 2])?
	xs.rotate(-2)
	expect_equal(xs, [1, 2, 3, 4, 5])?
	xs.rotate(7)
	expect_equal(xs, [3, 4, 5, 1, 2])?
	xs.rotate(5)
	expect_equal(xs, [3, 4, 5, 1, 2])?

	var empty = List[Int]()
	empty.rotate(3)
	expect_equal(empty, List[Int]())?

test "is_sorted and is_sorted_by":
	expect_true([1, 2, 2, 5].is_sorted())?
	expect_false([2, 1].is_sorted())?
	expect_true(List[Int]().is_sorted())?
	expect_true([3, 2, 1].is_sorted_by(fn a, b: b - a))?

test "sorted_by_key is stable":
	people := [Person("a", 30), Person("b", 20), Person("c", 30), Person("d", 10)]
	ordered := people.sorted_by_key(fn p: p.age)
	expect_equal(ordered.map(fn p: p.name.clone()), ["d", "b", "a", "c"])?
	expect_equal(people[0].name, "a")?

test "repeated copies the list":
	expect_equal([1, 2].repeated(3), [1, 2, 1, 2, 1, 2])?
	expect_equal([1, 2].repeated(0), List[Int]())?
	expect_equal(["x"].repeated(2), ["x", "x"])?

test "extend appends copies and leaves the argument":
	var xs = [1]
	more := [2, 3]
	xs.extend(more)
	xs.extend(List[Int]())
	expect_equal(xs, [1, 2, 3])?
	expect_equal(more, [2, 3])?

	var names = ["a"]
	names.extend(["b"])
	expect_equal(names, ["a", "b"])?

test "retain on Map and Set":
	var counts = {"a": 0, "b": 2, "c": 0, "d": 5}
	counts.retain(fn key, n: n != 0)
	expect_equal(counts.keys(), ["b", "d"])?

	var seen = Set([3, -1, 4, -5])
	seen.retain(fn n: n >= 0)
	expect_equal(seen.values(), [3, 4])?

test "Deque rotate turns the ring":
	var ring = Deque[Int]()
	for n in 1..5:
		ring.push_back(n)
	ring.rotate(1)
	expect_equal(ring.to_list(), [2, 3, 4, 1])?
	ring.rotate(-1)
	expect_equal(ring.to_list(), [1, 2, 3, 4])?
	ring.rotate(6)
	expect_equal(ring.to_list(), [3, 4, 1, 2])?

fn repeat_negative_empty() Unit:
	_result := List[Int]().repeated(-1)

test "repeated empty lists return without traversing the count":
	for count in [0, 1, 1000000, 9223372036854775807]:
		expect_equal(List[Int]().repeated(count), List[Int]())?
		expect_equal(List[String]().repeated(count), List[String]())?

	fault := expect_fault(repeat_negative_empty)?
	expect_equal(fault, "List.repeated: count -1 must not be negative")?

test "repeated nested lists remain independent copies":
	values := [[1, 2]]
	var repeated = values.repeated(2)
	repeated[0].append(3)
	expect_equal(values, [[1, 2]])?
	expect_equal(repeated, [[1, 2, 3], [1, 2]])?
