// conform: tags=lists,tier-core
// conform: phase=test
import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

fn at(xs List[Int], i Int) Int {
	return xs[i]
}

fn put(var xs List[Int], i, v Int) Void {
	xs[i] = v
}

// An in-range index takes the one-comparison path; a negative one counts from the end;
// both ends are checked.
test "an index counts from the end when negative" {
	xs := [10, 20, 30, 40]
	expect_equal(at(xs, 0), 10)?
	expect_equal(at(xs, 3), 40)?
	expect_equal(at(xs, -1), 40)?
	expect_equal(at(xs, -4), 10)?

	var ys = [1, 2, 3]
	put(ys, -1, 9)
	put(ys, 0, 7)
	put(ys, -3, 5)
	expect_equal(ys, [5, 2, 9])?
}

test "an index past either end faults" {
	xs := [1, 2, 3]
	message := expect_fault(() => { void at(xs, 3) })?
	message | expect_contains("index")?

	message2 := expect_fault(() => { void at(xs, -4) })?
	message2 | expect_contains("index")?

	big := expect_fault(() => { void at(xs, 9223372036854775807) })?
	big | expect_contains("index")?

	var zs = [1]
	small := expect_fault(() => { put(zs, -2, 0) })?
	small | expect_contains("index")?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
