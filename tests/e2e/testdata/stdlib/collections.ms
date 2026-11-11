import (
	RangeOptions,
	filled,
	flatten,
	map_from_entries,
	range_by from "@std/collections/collections.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

fn positive(value: Int) Bool: value > 0

fn twice(value: Int) Int: value * 2

fn duplicate(value: Int) List[Int]: [value, value]

fn sum(accumulator: Int, value: Int) Int: accumulator + value

fn parity(value: Int) Int: value % 2

test "list search callbacks empty identities and folding":
	list := [-1, 2, 0, 3]
	expect_false((list.find(positive) != 2 or list.find_last(positive) != 3))?
	expect_false(
		(list.find_index(positive) != 1 or list.find_last_index(positive) != 3)
	)?
	expect_equal(list.filter(positive).map(twice), [4, 6])?
	expect_equal(([1, 2]).flat_map(duplicate), [1, 1, 2, 2])?
	expect_false((list.fold(0, sum) != 4 or list.fold_right(0, sum) != 4))?

	empty: List[Int] := []
	expect_false(empty.any(positive) or not empty.all(positive))?
	expect_false(empty.first().is_some() or empty.last().is_some())?

	groups := ([1, 2, 3]).group_by(parity)
	expect_false(groups.get(1) != [1, 3] or groups.get(0) != [2])?

test "group_by keeps first-seen key order and element order across few and many buckets":
	values := 0..600
	few := values.group_by(fn(x: Int) Int: x % 3)
	expect_equal(few.keys(), [0, 1, 2])?

	var total = 0

	for k in 0..3:
		group := few.get(k).get()
		expect_equal(group.length(), 200)?

		for j in 0..200:
			expect_equal(group[j], j * 3 + k)?
			total += group[j]

	expect_equal(total, 599 * 600 / 2)?

	words := ["b", "a", "b", "c", "a", "b"].group_by(fn(w: String) String: w.clone())
	expect_equal(words.keys(), ["b", "a", "c"])?
	expect_equal(words.get("b"), ["b", "b", "b"])?
	expect_equal(words.get("c"), ["c"])?

	unique := values.group_by(fn(x: Int) Int: x)
	expect_equal(unique.length(), 600)?
	expect_equal(unique.get(599), [599])?

test "list mutation and clone keep separate storage":
	original := [1, 2, 3]
	var copy = original.clone()
	copy.splice(1, 1, [8, 9])
	expect_false(copy != [1, 8, 9, 3] or original != [1, 2, 3])?
	copy.fill(0, 1, 3)
	expect_equal(copy, [1, 0, 0, 3])?

	var overlapping = [1, 2, 3, 4]
	overlapping.copy_within(1, 0, 3)
	expect_equal(overlapping, [1, 1, 2, 3])?

test "maps preserve insertion order and overwrite duplicate keys":
	entries := [MapEntry("a", 1), MapEntry("b", 2), MapEntry("a", 3)]
	var map = map_from_entries(entries)
	expect_false(map.keys() != ["a", "b"] or map.values() != [3, 2])?
	map.add_default("a", 99)
	expect_equal(map.get("a"), 3)?

	var copy = map.clone()
	copy.remove("a")
	expect_false(copy.keys() != ["b"] or map.keys() != ["a", "b"])?
	expect_false(map.get("missing").is_some())?

test "set algebra removes duplicates and preserves values":
	left := ([1, 2, 2]).to_set()
	right := ([2, 3]).to_set()
	expect_equal(left.values(), [1, 2])?
	expect_equal(left.union(right).values(), [1, 2, 3])?
	expect_equal(left.intersection(right).values(), [2])?
	expect_equal(left.difference(right).values(), [1])?
	expect_equal(left.symmetric_difference(right).values(), [1, 3])?
	expect_false(not left.is_subset_of(left.union(right)))?
	expect_false(not left.is_disjoint_from(([3]).to_set()))?

test "empty intersections preserve owned string inputs":
	left := (["a long owned document identifier", "another owned identifier"]).to_set()
	var right = (["removed owned identifier"]).to_set()
	right.remove("removed owned identifier")

	var result = left.intersection(right)
	expect_true(result.is_empty())?
	result.add("new independent owned identifier")
	expect_equal(result.values(), ["new independent owned identifier"])?
	expect_equal(
		left.values(), ["a long owned document identifier", "another owned identifier"]
	)?
	expect_true(right.is_empty())?
	expect_true(right.intersection(left).is_empty())?

test "collection constructors validate bounds and exact limits":
	expect_equal((range_by(3, -1, -1, RangeOptions(max_items: 4))?), [3, 2, 1, 0])?
	expect_equal((filled("x", 2)?), ["x", "x"])?

	invalid: List[Int]! := error(Error("collection: invalid input", kind: "EINVAL"))
	expect_equal(range_by(0, 1, 0), invalid)?

	limited: List[Int]! := error(Error("collection: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(range_by(0, 3, 1, RangeOptions(max_items: 2)), limited)?

test "stepped ranges handle full-width spans and minimum negative steps":
	minimum := -9223372036854775808
	maximum := 9223372036854775807
	expect_equal(
		(range_by(minimum, maximum, maximum, RangeOptions(max_items: 3))?),
		[minimum, -1, (maximum - 1)]
	)?
	expect_equal(
		(range_by(maximum, minimum, minimum, RangeOptions(max_items: 2))?),
		[maximum, -1]
	)?
	expect_equal((range_by(0, minimum, minimum, RangeOptions(max_items: 1))?), [0])?

	limited: List[Int]! := error(Error("collection: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(
		range_by(minimum, maximum, maximum, RangeOptions(max_items: 2)), limited
	)?

test "range counts up by one":
	expect_equal((0..4), [0, 1, 2, 3])?

	none_between: List[Int] := []
	expect_false((2..2) != none_between or (5..1) != none_between)?
	expect_equal((-2..1), [-2, -1, 0])?

test "for over range counts without a list":
	var total = 0
	for index in 0..5:
		total += index
	expect_equal(total, 10)?

	var visits = 0
	for outer in 0..3:
		for inner in outer..3:
			visits += 1
	expect_equal(visits, 6)?

	var bound = 3
	var seen = 0

	for index in 0..bound:
		bound = 10
		seen += 1

	expect_equal(seen, 3)?

	var huge = 0
	for index in 9223372036854775800..9223372036854775807:
		huge += 1
	expect_equal(huge, 7)?

	var skipped = 0

	for index in 0..10:
		if index % 2 == 0: continue
		if index > 7: break

		skipped += index

	expect_equal(skipped, 16)?

	var callbacks: List[fn() Int] = []
	for index in 0..3:
		callbacks.append(fn: index)
	expect_equal(callbacks.map(fn call: call()), [0, 1, 2])?

test "huge sizes return LimitExceeded instead of exhausting memory":
	limited: List[Int]! := error(Error("collection: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(filled(1, 9223372036854775807), limited)?
	expect_equal(filled(1, 4611686018427387904, 9223372036854775807), limited)?
	expect_equal(range_by(0, 9223372036854775807, 1), limited)?

test "imported map add interoperates with with_entry":
	var values = Map[String, Int]()
	values.add("a", 1)
	values.add("b", 2)
	values.add(value: 3, "a")

	add := values.add
	add("c", 4)
	expect_false(values.keys() != ["a", "b", "c"] or values.values() != [3, 2, 4])?

test "flatten concatenates lists":
	expect_equal(flatten([[1, 2], [], [3]]), [1, 2, 3])?
	expect_equal(flatten(List[List[Int]]()), List[Int]())?

type JoinPoint:
	x: Int

test "List join renders any element type":
	expect_equal([1.5, 2.5].join(","), "1.5,2.5")?
	expect_equal([true, false].join("/"), "true/false")?
	expect_equal(
		[JoinPoint(1), JoinPoint(2)].join(";"), "JoinPoint(x: 1);JoinPoint(x: 2)"
	)?
	expect_equal(List[Int]().join(","), "")?

fn repeat_copy[T: Clonable](value: T) List[T]!:
	return filled(value, 2)

fn flatten_copy[T: Clonable](values: List[List[T]]) List[T]:
	return flatten(values)

test "filled copies nested values independently through generic and function calls":
	source := [1]
	var copies = repeat_copy(source)?
	copies[0].append(2)
	expect_equal(copies, [[1, 2], [1]])?
	expect_equal(source, [1])?

	repeat := filled[List[Int]]
	var via_function = repeat(source, 2, none)?
	via_function[1].append(3)
	expect_equal(via_function, [[1], [1, 3]])?
	expect_equal(source, [1])?

test "flatten copies nested elements through generic and function calls":
	source := [[[1]], [[2]]]
	var copies = flatten_copy(source)
	copies[0].append(3)
	expect_equal(copies, [[1, 3], [2]])?
	expect_equal(source, [[[1]], [[2]]])?

	concatenate := flatten[List[Int]]
	var via_function = concatenate(source)
	via_function[1].append(4)
	expect_equal(via_function, [[1], [2, 4]])?
	expect_equal(source, [[[1]], [[2]]])?
