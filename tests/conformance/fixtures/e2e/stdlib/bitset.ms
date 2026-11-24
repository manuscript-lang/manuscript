// conform: tags=stdlib-bitset,stdlib-testing,testing,tier-stdlib
// conform: phase=test
import (
	BitSet from "@std/collections/bitset.ms",
	expect_equal, expect_error, expect_false, expect_true from "@std/test/test.ms",
)

fn of(members List[Int]) BitSet! {
	var set = BitSet()
	for member in members {
		set.add(member)?
	}
	return ok(set)
}

test "add remove contains across word boundaries" {
	var set = of([0, 1, 63, 64, 65, 200])?
	expect_equal(set.values(), [0, 1, 63, 64, 65, 200])?
	expect_equal(set.length(), 6)?
	expect_true(set.contains(63))?
	expect_true(set.contains(64))?
	expect_false(set.contains(62))?
	expect_false(set.contains(100000))?
	expect_false(set.contains(-1))?
	set.remove(64)
	set.remove(999)
	set.remove(-5)
	expect_equal(set.values(), [0, 1, 63, 65, 200])?
	set.add(63)?
	expect_equal(set.length(), 5)?
}

test "next finds the following member" {
	set := of([5, 64, 130])?
	expect_equal(set.next(), 5)?
	expect_equal(set.next(5), 5)?
	expect_equal(set.next(6), 64)?
	expect_equal(set.next(65), 130)?
	expect_equal(set.next(131), null)?
	expect_equal(set.next(-3), 5)?
	expect_equal(BitSet().next(), null)?
}

test "set algebra matches Set" {
	a := of([1, 5, 63, 64, 130])?
	b := of([5, 63, 200])?
	small := of([5, 63])?
	one := of([1])?
	two := of([2])?
	expect_equal(a.union(b).values(), [1, 5, 63, 64, 130, 200])?
	expect_equal(a.intersection(b).values(), [5, 63])?
	expect_equal(a.difference(b).values(), [1, 64, 130])?
	expect_equal(a.symmetric_difference(b).values(), [1, 64, 130, 200])?
	expect_true(small.is_subset_of(a))?
	expect_true(a.is_superset_of(one))?
	expect_true(two.is_disjoint_from(a))?
	expect_false(a.is_disjoint_from(b))?
	expect_true(BitSet().is_subset_of(a))?
}

test "copies are independent and clear empties" {
	var a = of([1, 2])?
	var b = a.clone()
	b.add(3)?
	expect_equal(a.values(), [1, 2])?
	b.clear()
	expect_true(b.is_empty())?
	expect_equal(b.length(), 0)?
}

test "add rejects an index outside 0 through 1073741823 and changes nothing" {
	var set = BitSet()
	expect_equal((expect_error(set.add(-1))?).kind, "EINVAL")?
	expect_equal((expect_error(set.add(1073741824))?).kind, "EINVAL")?
	expect_true(set.is_empty())?
	set.add(1073741823)?
	expect_true(set.contains(1073741823))?
}
