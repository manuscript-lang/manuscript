// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn set_temporary() Void {
	return [0].set(0, 9)
}

fn append_temporary() Void {
	return [0].append(9)
}

fn pop_temporary() Int? {
	return [3, 4].pop()
}

test "a Void mutation of a temporary list returns Void" {
	set_temporary()
	append_temporary()

	unit_value Void := [0].set(0, 9)
	expect_equal(unit_value, void)?
}

test "a mutation of a temporary list keeps its extra result" {
	expect_equal(pop_temporary(), 4)?
}
