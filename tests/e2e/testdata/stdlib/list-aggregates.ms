from "@std/testing.ms" import expect_equal, expect_true

type Version:
    major: Int
    label: String

impl Comparable for Version:
    def compare(other: Version) -> Int:
        if self.major < other.major: return -1
        if self.major > other.major: return 1

        return 0

def ordered[T: Comparable](values: List[T]) -> List[T]:
    return values.sorted()

test "sorted orders Int, Float and String ascending without a comparator":
    let numbers = [3, 1, 2, -5, 1]
    try expect_equal(numbers.sorted(), [-5, 1, 1, 2, 3])
    try expect_equal(numbers, [3, 1, 2, -5, 1])
    try expect_equal([2.5, -1.0, 0.0].sorted(), [-1.0, 0.0, 2.5])
    try expect_equal(["pear", "apple", "fig"].sorted(), ["apple", "fig", "pear"])
    try expect_equal(List[Int]().sorted(), List[Int]())

    let small: List[Int8] = [3, 1, 2]
    let expected: List[Int8] = [1, 2, 3]
    try expect_equal(small.sorted(), expected)

test "sorted puts Float NaN last":
    let nan = 0.0 / 0.0
    let ordered_floats = [2.0, nan, 1.0, 0.5].sorted()
    try expect_equal(ordered_floats.take(3), [0.5, 1.0, 2.0])
    try expect_true(ordered_floats[3].is_nan())

test "sorted with a comparator":
    try expect_equal([1, 3, 2].sorted(lambda a, b: b - a), [3, 2, 1])

test "sorted is stable for user Comparable types":
    let versions = [Version(2, "b"), Version(1, "x"), Version(2, "a"), Version(1, "y")]
    let labels = versions.sorted().map(lambda v: v.label.clone())
    try expect_equal(labels, ["x", "y", "b", "a"])

test "sorted works through a generic Comparable bound":
    try expect_equal(ordered([3, 1, 2]), [1, 2, 3])
    try expect_equal(ordered(["b", "a"]), ["a", "b"])

test "sort orders the list in place":
    var numbers = [3, 1, 2]
    numbers.sort()
    try expect_equal(numbers, [1, 2, 3])
    numbers.sort(lambda a, b: b - a)
    try expect_equal(numbers, [3, 2, 1])

    var versions = [Version(2, "b"), Version(1, "x"), Version(2, "a")]
    versions.sort()
    try expect_equal(versions.map(lambda v: v.label.clone()), ["x", "b", "a"])

    var words = ["b", "c", "a"]
    words.sort()
    try expect_equal(words, ["a", "b", "c"])

test "sum adds Int, Float and sized numerics":
    try expect_equal([1, 2, 3].sum(), 6)
    try expect_equal(List[Int]().sum(), 0)
    try expect_equal([0.5, 1.5].sum(), 2.0)
    try expect_equal(List[Float]().sum(), 0.0)

    let small: List[Int8] = [100, 20, -3]
    let total: Int8 = 117
    try expect_equal(small.sum(), total)

    let narrow: List[Float32] = [1.5, 2.5]
    let narrow_total: Float32 = 4.0
    try expect_equal(narrow.sum(), narrow_total)

test "min and max return the first of equal elements and none when empty":
    let numbers = [3, 9, 2, 9, 2]
    try expect_equal(numbers.min(), some(2))
    try expect_equal(numbers.max(), some(9))
    try expect_true(List[Int]().min().is_none())
    try expect_true(List[String]().max().is_none())
    try expect_equal(["pear", "apple", "fig"].min(), some("apple"))
    try expect_equal([0.5, 2.5, -1.0].max(), some(2.5))

test "min and max over user Comparable types keep the first equal element":
    let versions = [Version(2, "b"), Version(1, "x"), Version(2, "a"), Version(1, "y")]
    try expect_equal(versions.min().get().label, "x")
    try expect_equal(versions.max().get().label, "b")

test "min and max copy the element":
    let versions = [Version(1, "x")]
    var copy = versions.max().get().clone()
    copy.major = 9
    try expect_equal(versions[0].major, 1)

test "Float compare orders NaN above every value and equal to itself":
    let nan = 0.0 / 0.0
    try expect_equal(nan.compare(1.0), 1)
    try expect_equal((1.0).compare(nan), -1)
    try expect_equal(nan.compare(nan), 0)
    try expect_equal((-0.0).compare(0.0), 0)
    try expect_equal((2.0).compare(1.0), 1)
