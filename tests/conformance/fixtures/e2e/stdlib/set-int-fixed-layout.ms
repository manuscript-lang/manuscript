// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

test "Set[Int] add ignores repeats and keeps insertion order":
	var s = Set[Int]([])
	for k in [5, -1, 5, 0, 9223372036854775807, -1, -9223372036854775807 - 1]:
		s.add(k)
	expect_equal(s.length(), 5)?
	expect_equal(s.values(), [5, -1, 0, 9223372036854775807, -9223372036854775807 - 1])?

test "Set[Int] contains agrees after growth, removal and reinsertion":
	var s = Set[Int]([])
	for i in 0..5000:
		s.add(i * 7919 % 10007)
	expect_equal(s.length(), 5000)?
	expect_true(s.contains(0))?
	expect_false(s.contains(10007))?
	s.remove(7919)
	expect_false(s.contains(7919))?
	s.add(7919)
	expect_true(s.contains(7919))?
	expect_equal(s.length(), 5000)?
	expect_false(Set[Int]([]).contains(1))?
