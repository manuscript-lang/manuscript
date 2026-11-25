// conform: tags=testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A call passes a variable to a `var` parameter plainly; the callee's signature says it
// changes it.

type Bag {
	items List[Int]
}

fn push_one(var values List[Int]) Void {
	values.append(1)
}

fn apply(change fn(var List[Int]) Void, var values List[Int]) Void {
	change(values)
}

test "var parameters take plain arguments" {
	var values List[Int] = []
	push_one(values)
	apply(push_one, values)

	var bag = Bag(items: [])
	push_one(bag.items)
	(values.length() + bag.items.length()) | expect_equal(3)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
