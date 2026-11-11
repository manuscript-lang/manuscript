// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, join from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

test "join concatenates parts in order":
	expect_equal(
		join([Bytes([1, 2]), Bytes([]), Bytes([255]), Bytes([0, 7])]),
		Bytes([1, 2, 255, 0, 7]),
	)?

test "join of nothing is empty":
	none_at_all: List[Bytes] := []
	expect_equal(join(none_at_all), Bytes([]))?
	expect_equal(join([Bytes([]), Bytes([])]), Bytes([]))?

test "join leaves its parts unchanged":
	parts := [Bytes([3]), Bytes([4, 5])]
	whole := join(parts)
	expect_equal(whole, Bytes([3, 4, 5]))?
	expect_equal(parts, [Bytes([3]), Bytes([4, 5])])?
