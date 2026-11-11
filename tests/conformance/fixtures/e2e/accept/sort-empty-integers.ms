// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "integer comparison sorts accept empty and singleton lists":
	empty := List[Int]()
	expect_equal(empty.sorted(fn a, b: a.compare(b)), List[Int]())?
	expect_equal(empty.sorted(fn a, b: b.compare(a)), List[Int]())?
	expect_equal(empty.sorted(), List[Int]())?
	expect_equal([7].sorted(fn a, b: a.compare(b)), [7])?
	expect_equal([7].sorted(fn a, b: b.compare(a)), [7])?

test "integer comparison sorts keep full-width ordering":
	values := [9223372036854775807, 0, -9223372036854775807 - 1, 0]
	expect_equal(
		values.sorted(fn a, b: a.compare(b)),
		[-9223372036854775807 - 1, 0, 0, 9223372036854775807],
	)?
	expect_equal(
		values.sorted(fn a, b: b.compare(a)),
		[9223372036854775807, 0, 0, -9223372036854775807 - 1],
	)?
