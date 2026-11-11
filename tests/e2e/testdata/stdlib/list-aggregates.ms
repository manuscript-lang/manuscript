import expect_equal, expect_true from "@std/test/test.ms"

type Version:
	major: Int
	label: String

fn Version.compare(other: Version) Int:
	if self.major < other.major: return -1
	if self.major > other.major: return 1

	return 0

fn ordered[T: Comparable & Clonable](values: List[T]) List[T]:
	return values.sorted()

test "sorted orders Int, Float and String ascending without a comparator":
	numbers := [3, 1, 2, -5, 1]
	expect_equal(numbers.sorted(), [-5, 1, 1, 2, 3])?
	expect_equal(numbers, [3, 1, 2, -5, 1])?
	expect_equal([2.5, -1.0, 0.0].sorted(), [-1.0, 0.0, 2.5])?
	expect_equal(["pear", "apple", "fig"].sorted(), ["apple", "fig", "pear"])?
	expect_equal(List[Int]().sorted(), List[Int]())?

	small: List[Int8] := [3, 1, 2]
	expected: List[Int8] := [1, 2, 3]
	expect_equal(small.sorted(), expected)?

test "sorted puts Float NaN last":
	nan := 0.0 / 0.0
	ordered_floats := [2.0, nan, 1.0, 0.5].sorted()
	expect_equal(ordered_floats.take(3), [0.5, 1.0, 2.0])?
	expect_true(ordered_floats[3].is_nan())?

test "sorted with a comparator":
	expect_equal([1, 3, 2].sorted(fn a, b: b - a), [3, 2, 1])?

test "sorted is stable for user Comparable types":
	versions := [Version(2, "b"), Version(1, "x"), Version(2, "a"), Version(1, "y")]
	labels := versions.sorted().map(fn v: v.label.clone())
	expect_equal(labels, ["x", "y", "b", "a"])?

test "sorted works through a generic Comparable bound":
	expect_equal(ordered([3, 1, 2]), [1, 2, 3])?
	expect_equal(ordered(["b", "a"]), ["a", "b"])?

test "sort orders the list in place":
	var numbers = [3, 1, 2]
	numbers.sort()
	expect_equal(numbers, [1, 2, 3])?
	numbers.sort(fn a, b: b - a)
	expect_equal(numbers, [3, 2, 1])?

	var versions = [Version(2, "b"), Version(1, "x"), Version(2, "a")]
	versions.sort()
	expect_equal(versions.map(fn v: v.label.clone()), ["x", "b", "a"])?

	var words = ["b", "c", "a"]
	words.sort()
	expect_equal(words, ["a", "b", "c"])?

test "sum adds Int, Float and sized numerics":
	expect_equal([1, 2, 3].sum(), 6)?
	expect_equal(List[Int]().sum(), 0)?
	expect_equal([0.5, 1.5].sum(), 2.0)?
	expect_equal(List[Float]().sum(), 0.0)?

	small: List[Int8] := [100, 20, -3]
	total: Int8 := 117
	expect_equal(small.sum(), total)?

	narrow: List[Float32] := [1.5, 2.5]
	narrow_total: Float32 := 4.0
	expect_equal(narrow.sum(), narrow_total)?

test "min and max return the first of equal elements and none when empty":
	numbers := [3, 9, 2, 9, 2]
	expect_equal(numbers.min(), 2)?
	expect_equal(numbers.max(), 9)?
	expect_true(List[Int]().min().is_none())?
	expect_true(List[String]().max().is_none())?
	expect_equal(["pear", "apple", "fig"].min(), "apple")?
	expect_equal([0.5, 2.5, -1.0].max(), 2.5)?

test "min and max over user Comparable types keep the first equal element":
	versions := [Version(2, "b"), Version(1, "x"), Version(2, "a"), Version(1, "y")]
	expect_equal(versions.min().get().label, "x")?
	expect_equal(versions.max().get().label, "b")?

test "min and max copy the element":
	versions := [Version(1, "x")]
	var copy = versions.max().get().clone()
	copy.major = 9
	expect_equal(versions[0].major, 1)?

test "Float compare orders NaN above every value and equal to itself":
	nan := 0.0 / 0.0
	expect_equal(nan.compare(1.0), 1)?
	expect_equal((1.0).compare(nan), -1)?
	expect_equal(nan.compare(nan), 0)?
	expect_equal((-0.0).compare(0.0), 0)?
	expect_equal((2.0).compare(1.0), 1)?
