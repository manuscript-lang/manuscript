// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// Arms that differ in checked index arithmetic become selects with a predicated overflow guard.
fn spread(values List[Int], base Int, last Int) Int:
	var front = 0
	var back = 0
	var total = 0
	for v in values:
		dst := if v < 0: base + front else: base + last - back
		total += dst
		if v < 0: front += 1
		else: back += 1
	return total

test "checked sums in both arms give the same result as branches":
	expect_equal(spread([1, -2, 3, -4, 5], 100, 10), 100 + 0 + 110 + 101 + 109 + 108)?
	expect_equal(spread([], 5, 5), 0)?

test "an overflow in the arm that is not taken does not fault":
	expect_equal(spread([-1], 9223372036854775800, 100), 9223372036854775800)?
