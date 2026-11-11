import (
	keep, measure from "@std/test/bench.ms",
	expect_equal, fail from "@std/test/test.ms",
)

fn sum_to(n: Int) Int:
	var total = 0
	for i in 0..n:
		total += i
	return total

bench "sums a range":
	expect_equal(sum_to(100), 4950)?

bench "breaks":
	fail("not measurable")?

test "is not a bench":
	expect_equal(sum_to(3), 3)?

bench "measures after setup":
	data := [3, 1, 2]
	measure(3, fn: keep(data.sorted().length()))?

bench "reports per operation" per 8:
	keep(8)?
