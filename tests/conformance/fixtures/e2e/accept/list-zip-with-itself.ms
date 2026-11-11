// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "a list zipped with itself pairs each element with itself":
	var names: List[String] = ["a", "b"]
	pairs := names.zip(names)
	expect_equal(pairs.length(), 2)?
	expect_equal(pairs[1].first, "b")?
	expect_equal(pairs[1].second, "b")?
	expect_equal(names.length(), 2)?
