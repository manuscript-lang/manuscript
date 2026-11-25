// conform: tags=testing,lists,maps,tier-stdlib
// conform: phase=test
import BigInt, big_int_of_int from "@std/math/math.ms"
import expect_equal, expect_false from "@std/test/test.ms"

// A BigInt is one shared handle that compares by value. A list, a map or an optional of them compared the
// handles, so two equal numbers held in separate objects were unequal.
fn million() BigInt {
	return big_int_of_int(1000000).multiply(big_int_of_int(1000000))
}

test "lists of equal BigInts are equal" {
	left := [million(), big_int_of_int(7)]
	right := [big_int_of_int(1000000000000), big_int_of_int(7)]
	expect_equal(left == right, true)?
	expect_false([million()] == [big_int_of_int(8)])?
}

test "maps and optionals of BigInts compare by value" {
	left := {"x": million()}
	right := {"x": big_int_of_int(1000000000000)}
	expect_equal(left == right, true)?
	expect_false(left == {"x": big_int_of_int(1)})?
	var first BigInt? = million()
	var second BigInt? = big_int_of_int(1000000000000)
	expect_equal(first == second, true)?
}
