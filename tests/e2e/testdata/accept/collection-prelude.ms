import TextError from "@std/core.ms"
import expect_equal, expect_false, fail from "@std/test.ms"

type Shape:
    case Circle(radius: Float)

type Point:
    x: Int
    y: Int

fn roll(i: Int) Int!TextError: ok(i)

fn count(values: List[String]) Int: values.length()

fn update[K: Hashable, V](var values: Map[K, V], key: K, value: V) Map[K, V]:
    values.add(key, value)
    return values.clone()

test "issue 187 programs need no collection imports":
    let shapes = [Shape.Circle(1.0)]
    try expect_false(shapes.length() != 1 or count(["/var", "log"]) != 2)

    var rolls: List[Int] = []

    for i in 0..5:
        if let n = roll(i):
            rolls.append(n)
        else:
            return fail("roll")

    try expect_equal(rolls.length(), 5)

    var points = Map[Point, Int]()
    points.add(Point(1, 2), 7)
    try expect_equal(points[Point(1, 2)], 7)

    let nested: List[Map[String, List[Int]]] = [{}, {"a": []}]
    try expect_equal(nested[1]["a"].length(), 0)

test "map add retains clones and insertion order":
    var values = {"a": 1, "b": 2}
    let copy = values.clone()
    values.add("a", 3)
    values.add("c", 4)
    values.add(value: 5, key: "b")
    values.add("d", 6)
    values.add(value: 7, key: "a")
    values.add("e", 8)
    try expect_equal(values.keys(), ["a", "b", "c", "d", "e"])
    try expect_equal(values.values(), [7, 5, 4, 6, 8])
    try expect_false(copy.keys() != ["a", "b"] or copy.values() != [1, 2])
    values.remove("b")
    values.add("b", 9)
    try expect_equal(values.keys(), ["a", "c", "d", "e", "b"])

    var payload = [1]
    var nested = Map[Int, List[Int]]()
    nested.add(1, payload.clone())
    payload.append(2)
    try expect_equal(nested[1], [1])
    try expect_equal(payload, [1, 2])

test "map add retains optional wrapping and generic bound calls":
    var values = Map[Int?, Int?]()
    values.add(1, 2)
    values.add(value: 3, key: 1)
    values.add(4, 5)
    try expect_equal(values[1].get(), 3)
    try expect_equal(values[4].get(), 5)

    var generic = update[Int?, Int?](var values, 6, 7)
    generic.add(8, 9)
    try expect_false(generic[6].get() != 7 or generic[8].get() != 9)

test "map add captures receivers and arguments in written order":
    var original = Map[Int, Int]()
    var visits = 0
    original.add(
        match present(1):
            _value:
                visits = 1
                1
            none: 0
        ,
        2
    )
    try expect_false(original[1] != 2 or visits != 1)

    var key = 3
    original.add(
        key,
        match present(1):
            _value:
                key = 4
                5
            none: 0
    )
    try expect_false(original[3] != 5 or original.contains(4))

    var order = 0
    original.add(
        value: match present(1):
            _value:
                order = 1
                7
            none: 0
        ,
        key: match present(1):
            _value:
                try expect_equal(order, 1)
                order = 2
                6
            none: 0
    )
    try expect_false(order != 2 or original[6] != 7)

fn present[T](value: T) T?:
    return value
