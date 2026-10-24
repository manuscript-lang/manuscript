from "@std/testing.ms" import expect_true
from "@std/math.ms" import max, max_of, min, min_of
from "@std/decimal.ms" import Decimal

type Version:
    major: Int

impl Comparable for Version:
    def compare(other: Comparable) -> Int:
        match other:
            case Version(value): return self.major - value.major
            case _: return 0

def larger[T: Comparable](left: T, right: T) -> T:
    return max(left, right)

test "max and min over built-in types":
    try expect_true((max(1, 2) == 2 and min(1, 2) == 1))
    try expect_true((max(1.5, 0.5) == 1.5 and min(1.5, 0.5) == 0.5))
    try expect_true((max("a", "b") == "b" and min("a", "b") == "a"))
    try expect_true((max(1.5d, 2.5d) == 2.5d))

test "float order puts NaN above every value":
    let nan = 0.0 / 0.0
    try expect_true((max(nan, 1.0).is_nan() and max(1.0, nan).is_nan()))
    try expect_true((min(nan, 1.0) == 1.0))

test "a source impl drives max, min, and generic bounds":
    try expect_true((max(Version(1), Version(3)).major == 3))
    try expect_true((min(Version(1), Version(3)).major == 1))
    try expect_true((larger(Version(5), Version(2)).major == 5))

test "compare through an explicit view":
    let left = Comparable(1)
    try expect_true((left.compare(Comparable(2)) < 0))
    try expect_true(((Comparable(Version(3)).compare(Comparable(Version(3))) == 0)))

test "max_of and min_of over a list":
    let numbers = [3, 9, 2]
    let empty: List[Int] = []
    try expect_true((max_of(numbers) == some(9) and min_of(numbers) == some(2)))
    try expect_true((max_of(empty).is_none() and min_of(empty).is_none()))
    try expect_true((max_of([Version(4), Version(8)]) == some(Version(8))))
