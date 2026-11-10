import (
    expect_contains, expect_fault, expect_true from "@std/test/test.ms",
    ListCopies from "@std/collections/collections.ms",
    StringBuilder from "@std/string.ms",
)

type Folded:
    name: String

impl Equal for Folded:
    fn equals(other: Folded) Bool:
        return true

impl Hashable for Folded:
    fn hash() Int:
        return 1

fn replace_first[T](var xs: List[T], value: T) List[T]:
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

    mapped := a.map(transform: fn(value: Folded) Folded: return Folded(name: "z"))
    (mapped.length() == 1) | try expect_true

test "builder":
    var sb = StringBuilder()
    append := sb.append
    append("a")
    append("é")
    (sb.build() == "aé") | try expect_true

test "abs of the minimum overflows":
    smallest := 0 - 9223372036854775807 - 1
    message := try expect_fault(
        fn:
            _ignored := smallest.abs()
    )
    message | try expect_contains("Int overflow")

test "negative split cap faults":
    message := try expect_fault(
        fn:
            _ignored := "a,b".split(separator: ",", max_parts: (0 - 1))
    )
    message | try expect_contains("max_parts must be nonnegative")

test "size and shape methods as values":
    xs := [10, 20, 30]
    var m = Map[String, Int]()
    m["a"] = 1

    s := Set([1, 2])
    length := xs.length
    is_empty := xs.is_empty
    keys := xs.keys
    entries := xs.entries
    windows := xs.windows
    chunks := xs.chunks
    map_length := m.length
    map_is_empty := m.is_empty
    map_entries := m.entries
    set_length := s.length
    set_is_empty := s.is_empty
    (length() == 3) | try expect_true
    (is_empty() == false) | try expect_true
    (keys().length() == 3) | try expect_true
    (entries().length() == 3) | try expect_true
    (windows(2).length() == 2) | try expect_true
    (chunks(2).length() == 2) | try expect_true
    (map_length() == 1) | try expect_true
    (map_is_empty() == false) | try expect_true
    (map_entries().length() == 1) | try expect_true
    (set_length() == 2) | try expect_true
    (set_is_empty() == false) | try expect_true

test "sorted as a value":
    view: ListCopies[Int] = [3, 1, 2]
    sort := view.sorted
    ordered := sort(compare: fn a, b: a - b)
    (ordered.get(index: 0) == 1) | try expect_true
    (ordered.get(index: 2) == 3) | try expect_true

test "take as a value":
    take := [3, 1, 2].take
    first := take(2)
    (first.length() == 2) | try expect_true
    (first.get(index: 0) == 3) | try expect_true

type EqualProbe:
    n: Int

fn same(a: Equal, b: Equal) Bool:
    return a.equals(b)

test "equals on built-in data":
    xs := [1, 2]
    ys := [1, 2]
    other := [9]
    probe := EqualProbe(n: 1)
    (xs.equals(ys)) | try expect_true
    (xs.equals(other) == false) | try expect_true
    ("x".equals("x")) | try expect_true
    (1.equals(2) == false) | try expect_true
    (probe.equals(EqualProbe(n: 1))) | try expect_true

    bound := probe.equals
    (bound(EqualProbe(n: 1))) | try expect_true
    (bound(EqualProbe(n: 2)) == false) | try expect_true

    text := "x".equals
    (text("x")) | try expect_true

test "built-in data passes as Equal":
    (same(1, 1)) | try expect_true
    (same(1, 2) == false) | try expect_true
    (same(EqualProbe(n: 1), EqualProbe(n: 1))) | try expect_true
    (same(EqualProbe(n: 1), 1) == false) | try expect_true

test "list and map literals pass as Equal":
    (same([1, 2], [1, 2])) | try expect_true
    (same([1, 2], [1]) == false) | try expect_true
    (same({"a": 1}, {"a": 1})) | try expect_true
    (same({"a": [1]}, {"a": [2]}) == false) | try expect_true

test "numeric and optional members as values":
    n := -7
    x := 2.5
    abs := n.abs
    sign := n.sign
    to_float := n.to_float
    to_decimal := n.to_decimal
    narrow := n.to_int8
    float_abs := (-x).abs
    is_nan := x.is_nan
    is_finite := x.is_finite
    hash := n.hash
    (abs() == 7) | try expect_true
    (sign() == -1) | try expect_true
    (to_float() == -7.0) | try expect_true
    (to_decimal().to_string() == "-7") | try expect_true
    (narrow().get(default: 0) == -7) | try expect_true
    (float_abs() == 2.5) | try expect_true
    (is_nan() == false) | try expect_true
    (is_finite()) | try expect_true
    (hash() == n.hash()) | try expect_true

test "native calls pass as Equal":
    (same("a".to_bytes(), "a".to_bytes())) | try expect_true
    (same("ab".slice(start: 0, end: 1), "ab".slice(start: 0, end: 1))) | try expect_true
    ("a".to_bytes().equals("a".to_bytes())) | try expect_true

test "native contract methods through an interface value":
    view: ListCopies[Int] = [3, 1, 2]
    (view.take(2).length() == 2) | try expect_true
    (view.reversed().get(index: 0) == 2) | try expect_true
    (view.clone().length() == 3) | try expect_true
