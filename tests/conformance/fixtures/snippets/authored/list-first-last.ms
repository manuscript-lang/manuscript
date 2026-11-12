// conform: tags=stdlib-collections,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn make(n: Int) List[Int]:
	var xs = List[Int]()
	for i in 0..n:
		xs.append(i + 1)
	return xs

test "first and last of scalar lists":
	expect_equal(List[Int]().first(), none)?
	expect_equal(List[Int]().last(), none)?
	expect_equal([4, 5, 6].first(), 4)?
	expect_equal([4, 5, 6].last(), 6)?
	expect_equal([1.5, 2.5].last(), 2.5)?
	expect_equal([true, false].first(), true)?
	small: List[UInt8] := [7, 8, 9]
	nine: UInt8 := 9
	expect_equal(small.last(), nine)?

test "first and last of a temporary list":
	expect_equal(make(0).first(), none)?
	expect_equal(make(3).first(), 1)?
	expect_equal(make(3).last(), 3)?

test "first and last of text lists copy the element":
	names := ["a", "b"]
	expect_equal(names.first(), "a")?
	expect_equal(names.last(), "b")?
