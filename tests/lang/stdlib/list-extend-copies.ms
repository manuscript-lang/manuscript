// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	flatten from "@std/collections/collections.ms",
	expect_equal from "@std/test/test.ms",
)

test "extend copies the argument, which stays usable" {
	var out = [1]
	extra := [2, 3]
	out.extend(extra)
	out.extend(extra)
	expect_equal(out, [1, 2, 3, 2, 3])?
	expect_equal(extra, [2, 3])?
}

test "extend grows owned elements and accepts an empty argument" {
	var words = ["a"]
	more := ["b", "c"]
	words.extend(more)
	words.extend([])

	var nested = [[1]]
	nested.extend([[2, 3], []])
	expect_equal(words, ["a", "b", "c"])?
	expect_equal(more, ["b", "c"])?
	expect_equal(nested, [[1], [2, 3], []])?
}

test "flatten copies every inner list in order" {
	lists := [[1, 2], [], [3]]
	expect_equal(flatten(lists), [1, 2, 3])?
	expect_equal(lists, [[1, 2], [], [3]])?
	expect_equal(flatten([["x"], ["y", "z"]]), ["x", "y", "z"])?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
