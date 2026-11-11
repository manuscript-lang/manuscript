import expect_equal from "@std/test/test.ms"

test "zip pairs by position and stops at the shorter list":
	numbers := [1, 2, 3]
	names := ["a", "b"]
	pairs := numbers.zip(names)
	expect_equal(pairs.length(), 2)?
	expect_equal(pairs[1].first, 2)?
	expect_equal(pairs[1].second, "b")?
	expect_equal(names.zip(numbers).length(), 2)?
	expect_equal(numbers.zip(List[String]()).length(), 0)?

test "chunks splits into copies and the last may be short":
	parts := [1, 2, 3, 4, 5, 6, 7].chunks(3)
	expect_equal(parts, [[1, 2, 3], [4, 5, 6], [7]])?
	expect_equal(List[Int]().chunks(3).length(), 0)?
	expect_equal(["x", "y"].chunks(5), [["x", "y"]])?

test "windows overlap and a short list has none":
	expect_equal([1, 2, 3, 4].windows(2), [[1, 2], [2, 3], [3, 4]])?
	expect_equal([1, 2].windows(3).length(), 0)?
	expect_equal(["a", "b", "c"].windows(3), [["a", "b", "c"]])?

test "partition splits by predicate keeping order":
	split := [1, 2, 3, 4, 5].partition(fn x: x % 2 == 0)
	expect_equal(split.matching, [2, 4])?
	expect_equal(split.rest, [1, 3, 5])?

	none_split := List[Int]().partition(fn x: x > 0)
	expect_equal(none_split.matching.length(), 0)?
	expect_equal(none_split.rest.length(), 0)?

test "flat_map infers its element type from list literals returned by a callback":
	expect_equal([1, 2].flat_map(fn x: [x, x * 10]), [1, 10, 2, 20])?
	expect_equal(["a"].flat_map(fn s: [s + "!"]), ["a!"])?
	expect_equal([1, 2].flat_map(fn x: (if x > 1: [x] else: [])), [2])?
