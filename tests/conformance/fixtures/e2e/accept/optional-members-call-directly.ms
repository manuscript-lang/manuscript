// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

fn fallback() Int: 9

test "optional members":
	present: Int? := 3
	absent: Int? := null
	expect_true(((present != null) and (present != null)))?
	expect_true(((absent == null) and (absent == null)))?
	expect_true(((present or 7) == 3))?
	expect_true(((absent or 7) == 7))?
	expect_true((absent or fallback()) == 9)?
	expect_true((present.map(fn(value: Int) Int: value + 1).get() == 4))?

	var items = List[Int]()
	expect_equal(items.get_or(index: 0, -1), -1)?
	items.append(value: 5)
	expect_true((items.get_or(index: 0, -1) == 5 and (items.first() or 0) == 5))?
