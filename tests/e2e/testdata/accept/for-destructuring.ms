import expect_equal from "@std/test/test.ms"

type Point:
	x: Int
	y: Int

test "for destructures list and record elements":
	pairs := [[1, 2], [3, 4]]
	var total = 0

	for [a, b] in pairs:
		total += a * b

	try expect_equal(total, 14)

	points := [Point(x: 1, y: 2), Point(x: 5, y: 6)]
	var sum = 0

	for {x, y: height} in points:
		sum += x + height

	try expect_equal(sum, 14)

	var firsts = ""

	for [first, _] in [["a", "b"], ["c", "d"]]:
		firsts = "{firsts}{first}"

	try expect_equal(firsts, "ac")

test "a lambda parameter destructures":
	rows := [[1, 2], [3, 4]]
	try expect_equal(rows.map(fn [a, b]: a - b), [-1, -1])
	try expect_equal(rows.fold(0, fn total, [a, b]: total + a * b), 14)
