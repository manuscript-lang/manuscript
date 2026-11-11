import expect_equal from "@std/test/test.ms"

fn first_copy[T: Clonable](xs: List[T]) T?:
	return xs[0].clone()

test "min and max keep the element width":
	small: List[Int8] := [5, -3, 7]
	mid: List[Int16] := [300, -300, 7]
	wide: List[Int32] := [2147483647, -2147483648, 0]
	floats: List[Float32] := [3.5, 1.25, -0.5]
	want_small_max: Int8? := 7
	try expect_equal(small.max(), want_small_max)

	want_small_min: Int8? := -3
	try expect_equal(small.min(), want_small_min)

	want_mid_max: Int16? := 300
	try expect_equal(mid.max(), want_mid_max)

	want_mid_min: Int16? := -300
	try expect_equal(mid.min(), want_mid_min)

	want_wide_max: Int32? := 2147483647
	try expect_equal(wide.max(), want_wide_max)

	want_wide_min: Int32? := -2147483648
	try expect_equal(wide.min(), want_wide_min)

	want_floats_max: Float32? := 3.5
	try expect_equal(floats.max(), want_floats_max)

	want_floats_min: Float32? := -0.5
	try expect_equal(floats.min(), want_floats_min)

test "clone of a generic sized number keeps its width":
	small: List[Int8] := [5, 3]
	want: Int8? := 5
	try expect_equal(first_copy(small), want)
