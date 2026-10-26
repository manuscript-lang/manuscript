from "@std/testing.ms" import expect_contains, expect_fault, expect_true
from "@std/string.ms" import StringBuilder
from "@std/collections.ms" import MapBuilder, SetBuilder

type Folded:
    name: String

impl Equal for Folded:
    def equals(other: Folded) -> Bool:
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

    let mapped = a.map(
        transform: lambda (value: Folded) -> Folded: return Folded(name: "z")
    )
    (mapped.length() == 1) | try expect_true

test "builder":
    var sb = StringBuilder()
    let append = sb.append
    append("a")
    append("é")
    (sb.build() == "aé") | try expect_true

test "sealed builder":
    var sb = StringBuilder()
    sb.build()

    let message = try expect_fault(lambda: sb.append(""))
    message | try expect_contains("builder is sealed")

test "sealed map and set builders fault on every add":
    var map_builder = MapBuilder[String, Int]()
    let map_sealed = map_builder.build()
    (try expect_fault(lambda: map_builder.add("a", 1))) | try expect_contains(
        "builder is sealed"
    )

    var set_builder = SetBuilder[Int]()
    let set_sealed = set_builder.build()
    (try expect_fault(lambda: set_builder.add(1))) | try expect_contains(
        "builder is sealed"
    )

test "unsealed set builder continues":
    var builder = SetBuilder[Int]()
    builder.add(1)

    let frozen = builder.build()
    (frozen.length() == 1) | try expect_true

test "abs of the minimum overflows":
    let smallest = 0 - 9223372036854775807 - 1
    let message = try expect_fault(
        lambda:
            let ignored = smallest.abs()
    )
    message | try expect_contains("Int overflow")

test "negative split cap faults":
    let message = try expect_fault(
        lambda:
            let ignored = "a,b".split(separator: ",", max_parts: some(0 - 1))
    )
    message | try expect_contains("max_parts must be nonnegative")

test "size and shape methods as values":
    let xs = [10, 20, 30]
    var m = Map[String, Int]()
    m["a"] = 1

    let s = Set([1, 2])
    let length = xs.length
    let is_empty = xs.is_empty
    let keys = xs.keys
    let entries = xs.entries
    let windows = xs.windows
    let chunks = xs.chunks
    let map_length = m.length
    let map_is_empty = m.is_empty
    let map_entries = m.entries
    let set_length = s.length
    let set_is_empty = s.is_empty
    (length() == 3) | try expect_true
    (is_empty() == False) | try expect_true
    (keys().length() == 3) | try expect_true
    (entries().length() == 3) | try expect_true
    (windows(2).length() == 2) | try expect_true
    (chunks(2).length() == 2) | try expect_true
    (map_length() == 1) | try expect_true
    (map_is_empty() == False) | try expect_true
    (map_entries().length() == 1) | try expect_true
    (set_length() == 2) | try expect_true
    (set_is_empty() == False) | try expect_true

test "sorted as a value":
    let sort = [3, 1, 2].sorted
    let ordered = sort(compare: lambda a, b: a - b)
    (ordered.get(index: 0) == 1) | try expect_true
    (ordered.get(index: 2) == 3) | try expect_true

type EqualProbe:
    n: Int

def same(a: Equal, b: Equal) -> Bool:
    return a.equals(b)

test "equals on built-in data":
    let xs = [1, 2]
    let ys = [1, 2]
    let other = [9]
    let probe = EqualProbe(n: 1)
    (xs.equals(ys)) | try expect_true
    (xs.equals(other) == False) | try expect_true
    ("x".equals("x")) | try expect_true
    (1.equals(2) == False) | try expect_true
    (probe.equals(EqualProbe(n: 1))) | try expect_true

    let bound = probe.equals
    (bound(EqualProbe(n: 1))) | try expect_true
    (bound(EqualProbe(n: 2)) == False) | try expect_true

    let text = "x".equals
    (text("x")) | try expect_true

test "built-in data passes as Equal":
    (same(1, 1)) | try expect_true
    (same(1, 2) == False) | try expect_true
    (same(EqualProbe(n: 1), EqualProbe(n: 1))) | try expect_true
    (same(EqualProbe(n: 1), 1) == False) | try expect_true

test "list and map literals pass as Equal":
    (same([1, 2], [1, 2])) | try expect_true
    (same([1, 2], [1]) == False) | try expect_true
    (same({"a": 1}, {"a": 1})) | try expect_true
    (same({"a": [1]}, {"a": [2]}) == False) | try expect_true

test "numeric and optional members as values":
    let n = -7
    let x = 2.5
    let abs = n.abs
    let sign = n.sign
    let to_float = n.to_float
    let to_decimal = n.to_decimal
    let narrow = n.to_int8
    let float_abs = (-x).abs
    let is_nan = x.is_nan
    let is_finite = x.is_finite
    let hash = n.hash
    (abs() == 7) | try expect_true
    (sign() == -1) | try expect_true
    (to_float() == -7.0) | try expect_true
    (to_decimal().to_string() == "-7") | try expect_true
    (narrow().get(default: 0) == -7) | try expect_true
    (float_abs() == 2.5) | try expect_true
    (is_nan() == False) | try expect_true
    (is_finite()) | try expect_true
    (hash() == n.hash()) | try expect_true

test "native calls pass as Equal":
    (same("a".to_bytes(), "a".to_bytes())) | try expect_true
    (same("ab".slice(start: 0, end: 1), "ab".slice(start: 0, end: 1))) | try expect_true
    ("a".to_bytes().equals("a".to_bytes())) | try expect_true
