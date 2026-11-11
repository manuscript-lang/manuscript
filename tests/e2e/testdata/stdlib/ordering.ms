import (
	max, min from "@std/math/math.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

test "min max and clamp on Int and the sized integers":
	try expect_equal((3).min(2), 2)
	try expect_equal((3).max(2), 3)
	try expect_equal((-5).clamp(0, 10), 0)
	try expect_equal((15).clamp(0, 10), 10)
	try expect_equal((7).clamp(0, 10), 7)

	small: Int8 := -3
	try expect_equal(small.min(4), -3)
	try expect_equal(small.clamp(0, 9), 0)

	wide: Int32 := 70000
	try expect_equal(wide.max(5), 70000)

test "unsigned integers order, compare and clamp":
	a: UInt8 := 250
	b: UInt8 := 3
	try expect_equal(a.compare(b), 1)
	try expect_equal(a.min(b), b)
	try expect_equal(a.max(b), a)
	try expect_equal(a.clamp(10, 200), 200)
	try expect_equal(min(a, b), b)

	big: UInt64 := 18446744073709551615
	try expect_equal(big.compare(1), 1)
	try expect_equal(big.min(1), 1)
	try expect_equal(big.clamp(0, 5), 5)

	w: UInt16 := 60000
	d: UInt32 := 4000000000
	try expect_equal(w.max(1), 60000)
	try expect_equal(d.min(5), 5)

	ordered: List[UInt32] := [d, 7, 4000000001]
	expected: List[UInt32] := [7, 4000000000, 4000000001]
	try expect_equal(ordered.sorted(), expected)

	top: UInt32 := 4000000001
	try expect_equal(ordered.max(), top)

test "min max and clamp on Float order NaN above every value":
	try expect_equal((2.5).min(1.5), 1.5)
	try expect_equal((2.5).clamp(0.0, 1.0), 1.0)

	nan := 0.0 / 0.0
	try expect_false(nan.max(1.0).compare(nan) != 0)
	try expect_equal(nan.min(1.0), 1.0)

	narrow: Float32 := 2.5
	try expect_equal(narrow.min(1.5), 1.5)

test "min max and clamp on String use scalar order":
	try expect_equal("apple".min("banana"), "apple")
	try expect_equal("apple".max("banana"), "banana")
	try expect_equal("zebra".clamp("a", "m"), "m")
	try expect_equal("Z".min("a"), "Z")
