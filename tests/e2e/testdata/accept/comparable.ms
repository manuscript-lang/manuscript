import {max, max_of, min, min_of} from "@std/math.ms"
import panic from "@std/faults.ms"
import Decimal from "@std/decimal.ms"

type Version:
    major: Int

impl Comparable for Version:
    fn compare(other: Comparable) -> Int:
        match other:
            Version(value): return self.major - value.major
            _: return 0

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn larger[T: Comparable](left: T, right: T) -> T:
    return max(left, right)

test "max and min over built-in types":
    check(ok: max(1, 2) == 2 and min(1, 2) == 1, name: "int")
    check(ok: max(1.5, 0.5) == 1.5 and min(1.5, 0.5) == 0.5, name: "float")
    check(ok: max("a", "b") == "b" and min("a", "b") == "a", name: "string")
    check(ok: max(1.5d, 2.5d) == 2.5d, name: "decimal")

test "float order puts NaN above every value":
    let nan = 0.0 / 0.0
    check(ok: max(nan, 1.0).is_nan() and max(1.0, nan).is_nan(), name: "max nan")
    check(ok: min(nan, 1.0) == 1.0, name: "min nan")

test "a source impl drives max, min, and generic bounds":
    check(ok: max(Version(major: 1), Version(major: 3)).major == 3, name: "max")
    check(ok: min(Version(major: 1), Version(major: 3)).major == 1, name: "min")
    check(ok: larger(Version(major: 5), Version(major: 2)).major == 5, name: "generic")

test "compare through an explicit view":
    let left = Comparable(value: 1)
    check(ok: left.compare(Comparable(value: 2)) < 0, name: "int view")
    check(
        ok: (
            Comparable(value: Version(major: 3)).compare(
                Comparable(value: Version(major: 3))
            ) == 0
        ),
        name: "equal"
    )

test "max_of and min_of over a list":
    let numbers = [3, 9, 2]
    let empty: List[Int] = []
    check(ok: max_of(numbers) == some(9) and min_of(numbers) == some(2), name: "ints")
    check(ok: max_of(empty).is_none() and min_of(empty).is_none(), name: "empty")
    check(
        ok: max_of([Version(major: 4), Version(major: 8)]) == some(
            Version(major: 8)
        ),
        name: "versions"
    )
