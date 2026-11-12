// conform: tags=maps,closures,control-flow,scope-cleanup,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A `String` key that `Map.update` takes on one branch only: the path that skips the
// call still owns the key and releases it, and the path that takes it releases it once.
fn count(lines: List[String]) Map[String, Int]:
	var counts: Map[String, Int] = {}

	for line in lines:
		key := line.trim()
		if line.length() > 3:
			counts.update(key, 0, fn n: n + 1)

	return counts

fn count_or_keep(lines: List[String]) Map[String, Int]:
	var counts: Map[String, Int] = {}

	for line in lines:
		key := line.trim()

		if line.length() > 3:
			counts.update(key, 0, fn n: n + 1)
		else:
			counts[key] = 100

	return counts

test "a key moved into update on one branch is released on the other":
	counts := count(["abcd", "xy", "abcd", "efgh", "z"])
	expect_equal(counts.length(), 2)?
	expect_equal(counts["abcd"], 2)?
	expect_equal(counts["efgh"], 1)?

test "update on one branch and an insert on the other":
	counts := count_or_keep(["abcd", "xy", "abcd", "z"])
	expect_equal(counts.length(), 3)?
	expect_equal(counts["abcd"], 2)?
	expect_equal(counts["xy"], 100)?
	expect_equal(counts["z"], 100)?

test "no branch taken leaves an empty map":
	counts := count(["a", "b"])
	expect_equal(counts.length(), 0)?
