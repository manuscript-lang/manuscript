from "@std/test.ms" import expect_equal

def first_copy[T: Clonable](xs: List[T]) -> Optional[T]:
    return some(xs[0].clone())

test "min and max keep the element width":
    let small: List[Int8] = [5, -3, 7]
    let mid: List[Int16] = [300, -300, 7]
    let wide: List[Int32] = [2147483647, -2147483648, 0]
    let floats: List[Float32] = [3.5, 1.25, -0.5]
    let want_small_max: Optional[Int8] = some(7)
    try expect_equal(small.max(), want_small_max)

    let want_small_min: Optional[Int8] = some(-3)
    try expect_equal(small.min(), want_small_min)

    let want_mid_max: Optional[Int16] = some(300)
    try expect_equal(mid.max(), want_mid_max)

    let want_mid_min: Optional[Int16] = some(-300)
    try expect_equal(mid.min(), want_mid_min)

    let want_wide_max: Optional[Int32] = some(2147483647)
    try expect_equal(wide.max(), want_wide_max)

    let want_wide_min: Optional[Int32] = some(-2147483648)
    try expect_equal(wide.min(), want_wide_min)

    let want_floats_max: Optional[Float32] = some(3.5)
    try expect_equal(floats.max(), want_floats_max)

    let want_floats_min: Optional[Float32] = some(-0.5)
    try expect_equal(floats.min(), want_floats_min)

test "clone of a generic sized number keeps its width":
    let small: List[Int8] = [5, 3]
    let want: Optional[Int8] = some(5)
    try expect_equal(first_copy(small), want)
