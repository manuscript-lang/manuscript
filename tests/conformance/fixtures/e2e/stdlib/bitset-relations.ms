// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	BitSet from "@std/collections/bitset.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

test "bitset predicates agree with algebra for unequal and trailing zero words":
	cases: List[List[Int]] := [
		[],
		[0],
		[1],
		[-1],
		[-9223372036854775808],
		[1, 0],
		[0, 1],
		[0, -9223372036854775808],
		[1, -1, 0],
		[0, 0, 0],
	]

	for a in cases:
		for b in cases:
			left := BitSet(words: a.clone())
			right := BitSet(words: b.clone())
			expect_equal(left.is_subset_of(right), left.difference(right).is_empty())?
			expect_equal(left.is_superset_of(right), right.difference(left).is_empty())?
			expect_equal(
				left.is_disjoint_from(right),
				left.intersection(right).is_empty(),
			)?
			expect_equal(left.words, a)?
			expect_equal(right.words, b)?

test "bitset predicates find decisive first and last words":
	for index in [0, 2047]:
		var left = BitSet()
		var right = BitSet()
		left.add(index)
		right.add(4095)
		expect_false(left.is_subset_of(right))?
		expect_false(right.is_superset_of(left))?
		expect_true(left.is_disjoint_from(right))?
		right.add(index)
		expect_true(left.is_subset_of(right))?
		expect_true(right.is_superset_of(left))?
		expect_false(left.is_disjoint_from(right))?

	var boundary = BitSet()
	boundary.add(63)
	boundary.add(64)
	expect_true(boundary.is_subset_of(boundary))?
	expect_true(boundary.is_superset_of(boundary))?
	expect_false(boundary.is_disjoint_from(boundary))?

test "bitset intersection and difference ignore words past the operand that bounds them":
	small := BitSet(words: [2])
	var large = BitSet()
	large.add(1)
	large.add(10000000)

	inter := small.intersection(large)
	expect_equal(inter.contains(1), true)?
	expect_equal(inter.contains(10000000), false)?
	expect_equal(inter.words.length(), 1)?

	diff := large.difference(small)
	expect_equal(diff.contains(1), false)?
	expect_equal(diff.contains(10000000), true)?
	expect_equal(small.difference(large).is_empty(), true)?
	expect_equal(small.union(large).contains(10000000), true)?
	expect_equal(small.symmetric_difference(large).contains(10000000), true)?
