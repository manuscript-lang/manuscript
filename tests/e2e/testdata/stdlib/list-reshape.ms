import expect_equal, expect_true, expect_false from "@std/test/test.ms"
import Deque from "@std/collections/deque.ms"

type Person:
    name: String
    age: Int

test "retain keeps matching elements in order":
    var xs = [1, 2, 3, 4, 5, 6]
    xs.retain(fn x: x % 2 == 0)
    try expect_equal(xs, [2, 4, 6])

    var words = ["a", "bb", "c", "dd"]
    words.retain(fn w: w.length() == 2)
    try expect_equal(words, ["bb", "dd"])

    var none_left = [1, 3]
    none_left.retain(fn x: x > 5)
    try expect_equal(none_left, List[Int]())

    var empty = List[Int]()
    empty.retain(fn x: true)
    try expect_equal(empty, List[Int]())

test "compact collapses runs only":
    var xs = [1, 1, 2, 2, 2, 1, 3, 3]
    xs.compact()
    try expect_equal(xs, [1, 2, 1, 3])

    var one = [7]
    one.compact()
    try expect_equal(one, [7])

    var words = ["a", "A", "b"]
    words.compact_by(fn a, b: a.lower() == b.lower())
    try expect_equal(words, ["a", "b"])

test "rotate wraps in both directions":
    var xs = [1, 2, 3, 4, 5]
    xs.rotate(2)
    try expect_equal(xs, [3, 4, 5, 1, 2])
    xs.rotate(-2)
    try expect_equal(xs, [1, 2, 3, 4, 5])
    xs.rotate(7)
    try expect_equal(xs, [3, 4, 5, 1, 2])
    xs.rotate(5)
    try expect_equal(xs, [3, 4, 5, 1, 2])

    var empty = List[Int]()
    empty.rotate(3)
    try expect_equal(empty, List[Int]())

test "is_sorted and is_sorted_by":
    try expect_true([1, 2, 2, 5].is_sorted())
    try expect_false([2, 1].is_sorted())
    try expect_true(List[Int]().is_sorted())
    try expect_true([3, 2, 1].is_sorted_by(fn a, b: b - a))

test "sorted_by_key is stable":
    let people = [Person("a", 30), Person("b", 20), Person("c", 30), Person("d", 10)]
    let ordered = people.sorted_by_key(fn p: p.age)
    try expect_equal(ordered.map(fn p: p.name.clone()), ["d", "b", "a", "c"])
    try expect_equal(people[0].name, "a")

test "repeated copies the list":
    try expect_equal([1, 2].repeated(3), [1, 2, 1, 2, 1, 2])
    try expect_equal([1, 2].repeated(0), List[Int]())
    try expect_equal(["x"].repeated(2), ["x", "x"])

test "remove_if on Map and Set":
    var counts = {"a": 0, "b": 2, "c": 0, "d": 5}
    counts.remove_if(fn key, n: n == 0)
    try expect_equal(counts.keys(), ["b", "d"])

    var seen = Set([3, -1, 4, -5])
    seen.remove_if(fn n: n < 0)
    try expect_equal(seen.values(), [3, 4])

test "Deque rotate turns the ring":
    var ring = Deque[Int]()
    for n in 1..5:
        ring.push_back(n)
    ring.rotate(1)
    try expect_equal(ring.to_list(), [2, 3, 4, 1])
    ring.rotate(-1)
    try expect_equal(ring.to_list(), [1, 2, 3, 4])
    ring.rotate(6)
    try expect_equal(ring.to_list(), [3, 4, 1, 2])
