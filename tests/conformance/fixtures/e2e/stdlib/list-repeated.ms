// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"
import filled from "@std/collections/collections.ms"

test "repeated repeats scalars and short blocks in order":
	expect_equal([1, 2].repeated(3), [1, 2, 1, 2, 1, 2])?
	expect_equal([7].repeated(5), [7, 7, 7, 7, 7])?
	expect_equal([1].repeated(0), [])?

test "repeated of an empty list is empty":
	empty: List[Int] := []
	expect_equal(empty.repeated(5), [])?

test "repeated clones strings and nested lists independently":
	expect_equal(["a", "bc"].repeated(2), ["a", "bc", "a", "bc"])?
	var nested = [[1], [2, 3]].repeated(2)
	nested[0].append(9)
	expect_equal(nested, [[1, 9], [2, 3], [1], [2, 3]])?

test "filled builds a list of copies":
	expect_equal(filled(0, 4, none).get([]), [0, 0, 0, 0])?
	expect_equal(filled("x", 3, none).get([]), ["x", "x", "x"])?
