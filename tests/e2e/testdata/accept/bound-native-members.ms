from "@std/testing.ms" import expect_contains, expect_fault, expect_true
from "@std/string.ms" import StringBuilder
from "@std/collections.ms" import MapBuilder, SetBuilder
from "@std/math.ms" import abs_int

type Folded:
    name: String

impl Equal for Folded:
    def equals(other: Equal) -> Bool:
        return True

impl Hashable for Folded:
    def hash() -> Int:
        return 1

def replace_first[T](var xs: List[T], value: T) -> List[T]:
    xs.set(index: 0, value: value)
    return xs.clone()

test "string members":
    ("  a,b ".trim().split(separator: ",").length() == 2) | try expect_true
    ("abc".upper() == "ABC") | try expect_true

test "list members":
    var xs = [1, 2, 3]
    xs.set(index: -1, value: 9)
    (xs.get(index: 2) == 9) | try expect_true
    (replace_first(xs: var xs, value: 5).get(index: 0) == 5) | try expect_true
    (xs.contains(value: 9)) | try expect_true

test "custom equality is kept for bound members":
    var a = Set[Folded]()
    a.add(value: Folded(name: "x"))
    a.add(value: Folded(name: "y"))
    (a.length() == 1) | try expect_true

    let mapped = a.map(transform: lambda (value: Folded) -> Folded: return Folded(name: "z"))
    (mapped.length() == 1) | try expect_true

test "builder":
    var sb = StringBuilder()
    let append = sb.append
    append("a")
    append("é")
    (sb.freeze() == "aé") | try expect_true

test "sealed builder":
    var sb = StringBuilder()
    sb.freeze()

    let message = try expect_fault(lambda: sb.append(""))
    message | try expect_contains("builder is sealed")

test "sealed map and set builders fault on every add":
    var map_builder = MapBuilder[String, Int]()
    let map_sealed = map_builder.freeze()
    (try expect_fault(lambda: map_builder.add("a", 1))) | try expect_contains(
        "builder is sealed"
    )

    var set_builder = SetBuilder[Int]()
    let set_sealed = set_builder.freeze()
    (try expect_fault(lambda: set_builder.add(1))) | try expect_contains(
        "builder is sealed"
    )

test "unsealed set builder continues":
    var builder = SetBuilder[Int]()
    builder.add(1)

    let frozen = builder.freeze()
    (frozen.length() == 1) | try expect_true

test "abs_int of the minimum overflows":
    let smallest = 0 - 9223372036854775807 - 1
    let message = try expect_fault(
        lambda:
            let ignored = abs_int(value: smallest)
    )
    message | try expect_contains("Int overflow")

test "negative split cap faults":
    let message = try expect_fault(
        lambda:
            let ignored = "a,b".split(separator: ",", max_parts: some(0 - 1))
    )
    message | try expect_contains("max_parts must be nonnegative")
