// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Point {
	x Int
	y Int
}

test "for destructures list and record elements" {
	pairs := [[1, 2], [3, 4]]
	var total = 0

	for [a, b] in pairs {
		total += a * b
	}

	expect_equal(total, 14)?

	points := [Point(x: 1, y: 2), Point(x: 5, y: 6)]
	var sum = 0

	for {x, y: height} in points {
		sum += x + height
	}

	expect_equal(sum, 14)?

	var firsts = ""

	for [first, _] in [["a", "b"], ["c", "d"]] {
		firsts = f"{firsts}{first}"
	}

	expect_equal(firsts, "ac")?
}

test "a lambda parameter destructures" {
	rows := [[1, 2], [3, 4]]
	expect_equal(rows.map(([a, b]) => a - b), [-1, -1])?
	expect_equal(rows.fold(0, (total, [a, b]) => total + a * b), 14)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
