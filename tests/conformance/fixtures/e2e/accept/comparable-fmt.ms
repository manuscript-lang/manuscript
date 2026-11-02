# conform: tags=control-flow,decimal,formatter,generics,interfaces,lists,match,modules,optional,parser,records,stdlib-decimal,stdlib-math,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/comparable.ms
import expect_true from "@std/test/test.ms"
import max, min from "@std/math/math.ms"
import Decimal from "@std/math/decimal.ms"

type Version:
    major: Int

impl Comparable for Version:
    fn compare(other: Version) Int:
        return self.major - other.major

fn larger[T: Comparable](left: T, right: T) T:
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
    let left: Comparable = 1
    try expect_true((left.compare(2) < 0))
    try expect_true(((Version(3).compare(Version(3)) == 0)))

test "max and min over a list":
    let numbers = [3, 9, 2]
    let empty: List[Int] = []
    try expect_true((numbers.max() == 9 and numbers.min() == 2))
    try expect_true((empty.max().is_none() and empty.min().is_none()))
    try expect_true(([Version(4), Version(8)].max() == Version(8)))
