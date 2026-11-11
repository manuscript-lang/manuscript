import expect_equal from "@std/test/test.ms"

fn set_temporary() Unit:
	return [0].set(0, 9)

fn append_temporary() Unit:
	return [0].append(9)

fn pop_temporary() Int?:
	return [3, 4].pop()

test "a Unit mutation of a temporary list returns Unit":
	set_temporary()
	append_temporary()

	unit_value: Unit := [0].set(0, 9)
	try expect_equal(unit_value, unit)

test "a mutation of a temporary list keeps its extra result":
	try expect_equal(pop_temporary(), 4)
