import {expect_equal, expect_false, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

type Shape:
    case Circle(radius: Float)

type Point:
    x: Int
    y: Int

fn roll(i: Int) -> Result[Int, String]: ok(i)

fn count(values: List[String]) -> Int: values.length()

fn update[K: Hashable, V](values: Map[K, V], key: K, value: V) -> Map[K, V]:
    return values.add(key, value)

test "issue 187 programs need no collection imports":
    let shapes = [Shape.Circle(1.0)]
    (shapes.length() != 1 or count(["/var", "log"]) != 2) | try expect_false
    var rolls: List[Int] = []

    for i in range(0, 5):
        match roll(i):
            ok(n): rolls.append(n)
            error(_): return fail("roll")

    rolls.length() | try expect_equal(expected: 5)
    let points = Map[Point, Int]()
    points.add(Point(1, 2), 7)
    points.get(Point(1, 2)).unwrap() | try expect_equal(expected: 7)
    let nested: List[Map[String, List[Int]]] = [{}, {"a": []}]
    nested[1].unwrap().get("a").unwrap().length() | try expect_equal(expected: 0)

test "map add returns receiver and retains aliases clone and insertion order":
    let values = {"a": 1, "b": 2}
    let alias = values
    let copy = values.clone()
    let returned = values.add("a", 3)
    returned.add(key: "c", value: 4)
    alias.add(value: 5, key: "b")
    let bound = values.add
    bound("d", 6)
    bound(value: 7, key: "a")
    values.add("e", 8)
    alias.keys() | try expect_equal(expected: ["a", "b", "c", "d", "e"])
    alias.values() | try expect_equal(expected: [7, 5, 4, 6, 8])
    (copy.keys() != ["a", "b"] or copy.values() != [1, 2]) | try expect_false
    values.remove("b").add("b", 9)
    values.keys() | try expect_equal(expected: ["a", "c", "d", "e", "b"])
    let payload = [1]
    let nested = Map[Int, List[Int]]().add(1, payload)
    payload.append(2)
    nested.get(1).unwrap() | try expect_equal(expected: [1, 2])

test "map add retains optional wrapping and generic bound calls":
    let values = Map[Optional[Int], Optional[Int]]()
    values.add(1, 2)
    values.add(value: 3, key: 1)
    let bound = values.add
    bound(4, 5)
    values.get(1).unwrap().unwrap() | try expect_equal(expected: 3)
    values.get(4).unwrap().unwrap() | try expect_equal(expected: 5)
    let generic = update[Optional[Int], Optional[Int]](values, some(6), some(7))
    generic.add(8, 9)
    (values.get(6).unwrap().unwrap() != 7 or values.get(8).unwrap().unwrap() != 9) | try expect_false

test "map add captures receivers and arguments in written order":
    let original = Map[Int, Int]()
    var selected = original
    let other = Map[Int, Int]()
    selected.add(
        match some(1):
            some(_):
                selected = other
                1
            none: 0
        ,
        2
    )
    (original.get(1).unwrap() != 2 or not other.is_empty()) | try expect_false
    var key = 3
    original.add(
        key,
        match some(1):
            some(_):
                key = 4
                5
            none: 0
    )
    (original.get(3).unwrap() != 5 or original.contains(4)) | try expect_false
    var order = 0
    original.add(
        value: match some(1):
            some(_):
                order = 1
                7
            none: 0
        ,
        key: match some(1):
            some(_):
                order | try expect_equal(expected: 1)
                order = 2
                6
            none: 0
    )
    (order != 2 or original.get(6).unwrap() != 7) | try expect_false
