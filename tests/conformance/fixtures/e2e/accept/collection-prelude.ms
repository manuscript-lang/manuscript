# conform: tags=aliasing,alternatives,control-flow,faults,lists,maps,match,modules,mutation,numbers,optional,records,stdlib-collections,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/collection-prelude.ms
import {TextError} from "@std/errors.ms"
import {expect_equal, expect_false, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

type Shape:
    case Circle(radius: Float)

type Point:
    x: Int
    y: Int

fn roll(i: Int) Result[Int, TextError]: ok(i)

fn count(values: List[String]) Int: values.length()

fn update[K: Hashable, V](values: Map[K, V], key: K, value: V) Map[K, V]:
    return values.add(key, value)

test "issue 187 programs need no collection imports":
    let shapes = [Shape.Circle(1.0)]
    try expect_false(shapes.length() != 1 or count(["/var", "log"]) != 2)
    let rolls: List[Int] = []

    for i in range(0, 5):
        if let n = roll(i):
            rolls.append(n)
        else:
            return fail("roll")

    try expect_equal(rolls.length(), 5)
    let points = Map[Point, Int]()
    points.add(Point(1, 2), 7)
    try expect_equal(points.get(Point(1, 2)).get(), 7)
    let nested: List[Map[String, List[Int]]] = [{}, {"a": []}]
    try expect_equal(nested[1].get("a").get().length(), 0)

test "map add returns receiver and retains aliases clone and insertion order":
    let values = {"a": 1, "b": 2}
    let alias = values
    let copy = values.clone()
    let returned = values.add("a", 3)
    returned.add("c", 4)
    alias.add(value: 5, key: "b")
    let bound = values.add
    bound("d", 6)
    bound(value: 7, key: "a")
    values.add("e", 8)
    try expect_equal(alias.keys(), ["a", "b", "c", "d", "e"])
    try expect_equal(alias.values(), [7, 5, 4, 6, 8])
    try expect_false(copy.keys() != ["a", "b"] or copy.values() != [1, 2])
    values.remove("b").add("b", 9)
    try expect_equal(values.keys(), ["a", "c", "d", "e", "b"])
    let payload = [1]
    let nested = Map[Int, List[Int]]().add(1, payload)
    payload.append(2)
    try expect_equal(nested.get(1).get(), [1, 2])

test "map add retains optional wrapping and generic bound calls":
    let values = Map[Optional[Int], Optional[Int]]()
    values.add(1, 2)
    values.add(value: 3, key: 1)
    let bound = values.add
    bound(4, 5)
    try expect_equal(values.get(1).get().get(), 3)
    try expect_equal(values.get(4).get().get(), 5)
    let generic = update[Optional[Int], Optional[Int]](values, some(6), some(7))
    generic.add(8, 9)
    try expect_false(values.get(6).get().get() != 7 or values.get(8).get().get() != 9)

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
    try expect_false(original.get(1).get() != 2 or not other.is_empty())
    var key = 3
    original.add(
        key,
        match some(1):
            some(_):
                key = 4
                5
            none: 0
    )
    try expect_false(original.get(3).get() != 5 or original.contains(4))
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
                try expect_equal(order, 1)
                order = 2
                6
            none: 0
    )
    try expect_false(order != 2 or original.get(6).get() != 7)
