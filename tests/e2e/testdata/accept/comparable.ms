import {max, max_of, min, min_of} from "@std/math.ms"
import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"

type Version:
    major: Int

impl Comparable for Version:
    fn compare(other: Comparable) Int:
        match other:
            Version(value): return self.major - value.major
            _: return 0

fn check(ok: Bool, name: String) Unit:
    if not ok:
        return panic(name)

fn larger[T: Comparable](left: T, right: T) T:
    return max(left, right)

test "max and min over built-in types":
    check(max(1, 2) == 2 and min(1, 2) == 1, "int")
    check(max(1.5, 0.5) == 1.5 and min(1.5, 0.5) == 0.5, "float")
    check(max("a", "b") == "b" and min("a", "b") == "a", "string")
    check(max(1.5d, 2.5d) == 2.5d, "decimal")

test "float order puts NaN above every value":
    let nan = 0.0 / 0.0
    check(max(nan, 1.0).is_nan() and max(1.0, nan).is_nan(), "max nan")
    check(min(nan, 1.0) == 1.0, "min nan")

test "a source impl drives max, min, and generic bounds":
    check(max(Version(1), Version(3)).major == 3, "max")
    check(min(Version(1), Version(3)).major == 1, "min")
    check(larger(Version(5), Version(2)).major == 5, "generic")

test "compare through an explicit view":
    let left = Comparable(1)
    check(left.compare(Comparable(2)) < 0, "int view")
    check((Comparable(Version(3)).compare(Comparable(Version(3))) == 0), "equal")

test "max_of and min_of over a list":
    let numbers = [3, 9, 2]
    let empty: List[Int] = []
    check(max_of(numbers) == some(9) and min_of(numbers) == some(2), "ints")
    check(max_of(empty).is_none() and min_of(empty).is_none(), "empty")
    check(max_of([Version(4), Version(8)]) == some(Version(8)), "versions")
