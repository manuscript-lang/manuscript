// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "a reserve far beyond memory is a hint and the list still grows":
	var xs = List[Int](reserve: 9223372036854775807)
	expect_equal(xs.length(), 0)?
	xs.append(1)
	xs.append(2)
	expect_equal(xs.length(), 2)?

test "negative reserve preallocates nothing":
	var xs = List[Int](reserve: -5)
	xs.append(7)
	expect_equal(xs[0], 7)?
