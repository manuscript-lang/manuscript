// conform: tags=ownership,lists,tier-core,testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `slice` answers a view of the list. A consumer that takes ownership of the answer (`get_or` moves the
// payload out, a `for` loop over a temporary consumes it) must get a copy: freeing or growing the view
// as an owner would release the elements the source list still holds.
fn churn() Int {
	var junk = List[String]()
	for i in 0..200 {
		junk.append(f"item number {i} padding padding")
	}
	return junk.length()
}

fn rest_of(versions List[String]) List[String] {
	tail := versions.slice(1, versions.length()).clone().get_or([])
	return tail.clone()
}

test "a list taken out of a slice result can be grown" {
	versions := ["go", "ms", "rust", "rust-checked"]
	var rotated = rest_of(versions)
	rotated.append("x")
	expect_equal(rotated.length(), 4)?
	expect_equal(churn(), 200)?
	expect_equal(versions[1], "ms")?
}

test "a loop over a slice result keeps the source elements" {
	parts := ["a", "b", "1", "2", "3"]
	var total = 0
	for p in parts.slice(2, parts.length()).clone().get_or([]) {
		total += p.parse_int() or 0
	}
	expect_equal(total, 6)?
	expect_equal(churn(), 200)?
	expect_equal(parts[4], "3")?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
