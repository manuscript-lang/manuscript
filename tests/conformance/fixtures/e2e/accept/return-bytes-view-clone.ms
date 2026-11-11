// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

fn middle(bytes: Bytes) Bytes:
	return bytes.view(1, 3).clone()

fn local_middle() Bytes:
	bytes := Bytes([10, 20, 30])
	return bytes.view(1, 3).clone()

test "a cloned view of a parameter or a local can be returned":
	expect_equal(middle(Bytes([1, 2, 3, 4])), Bytes([2, 3]))?
	expect_equal(local_middle(), Bytes([20, 30]))?
