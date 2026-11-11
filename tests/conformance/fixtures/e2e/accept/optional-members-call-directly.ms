// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

fn fallback() Int: 9

test "optional members":
	present: Int? := 3
	absent: Int? := none
	expect_true((present.is_some() and present.is_some()))?
	expect_true((absent.is_none() and absent.is_none()))?
	expect_true((present.get(default: 7) == 3))?
	expect_true((absent.get(default: 7) == 7))?
	expect_true((absent.or_else(create: fn() Int?: fallback()).get() == 9))?
	expect_true((present.map(fn(value: Int) Int: value + 1).get() == 4))?

	var items = List[Int]()
	expect_equal(items.get(index: 0, default: -1), -1)?
	items.append(value: 5)
	expect_true(
		(
			items.get(index: 0, default: -1) == 5
			and items.first().get(default: 0) == 5
		)
	)?
