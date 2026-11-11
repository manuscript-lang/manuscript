import (
	promise from "@std/concurrency/promise.ms",
	expect_equal from "@std/test/test.ms",
)

test "try inside a loop over a list of promises":
	a := promise(fn: ok(1))
	b := promise(fn: ok(2))
	var total = 0

	for p in [a, b]:
		value := p.wait()?
		total += value

	expect_equal(total, 3)?
