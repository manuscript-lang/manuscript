// conform: tags=testing,tier-core
// conform: phase=test
import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

type Number = Int | Int8 | Float | Float32

fn total[T: Number](values: List[T]) T:
	var sum: T = 0
	for v in values:
		sum += v
	return sum

fn largest[T: Number](values: List[T]) T:
	var best: T = 0
	for v in values:
		if v > best: best = v
	return best

test "one body sums every member of the set":
	expect_equal(total([1, 2, 3]), 6)?
	expect_equal(total([1.5, 2.5]), 4.0)?
	expect_equal(total(List[Int]()), 0)?
	expect_equal(total(List[Float]()), 0.0)?

	narrow: List[Float32] := [0.5, 0.25]
	expect_equal(total(narrow), 0.75)?
	expect_equal(largest([3, 9, 4]), 9)?

test "the standard sum is the same method":
	expect_equal([1, 2, 3].sum(), 6)?
	expect_equal([1.5, 2.5].sum(), 4.0)?

fn overflow() Unit:
	small: List[Int8] := [100, 28]
	_ := total(small)

test "sized integers keep their overflow fault":
	message := expect_fault(overflow)?
	expect_contains(message, "Int overflow")?
