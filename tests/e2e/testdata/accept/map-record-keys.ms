from "@std/test.ms" import expect_true

type Point:
    x: Int
    y: Int

type Tagged:
    id: Int32
    ok: Bool
    n: Int

type Named:
    name: String
    n: Int

type Folded:
    n: Int

impl Hashable for Folded:
    def hash() -> Int:
        return 0

impl Equal for Folded:
    def equals(other: Folded) -> Bool:
        return True

test "plain record keys":
    var m = Map[Point, Int]()
    for i in 0..50:
        m.add(Point(x: i, y: i * 2), i)
    try expect_true(m.length() == 50)
    try expect_true(m.get(Point(y: 20, x: 10)).get(-1) == 10)
    try expect_true(m.get(Point(x: 10, y: 21)).get(-1) == -1)
    m.add(Point(x: 3, y: 6), 99)
    try expect_true(m.length() == 50 and m.get(Point(x: 3, y: 6)).get(-1) == 99)

test "padded and mixed width keys":
    var m = Map[Tagged, Int]()
    m.add(Tagged(id: 1, ok: True, n: 5), 1)
    m.add(Tagged(id: 1, ok: False, n: 5), 2)
    try expect_true(m.get(Tagged(n: 5, ok: True, id: 1)).get(0) == 1)
    try expect_true(m.get(Tagged(n: 5, ok: False, id: 1)).get(0) == 2)
    try expect_true(m.get(Tagged(n: 6, ok: False, id: 1)).get(0) == 0)

test "record keys holding strings use the general path":
    var m = Map[Named, Int]()
    m.add(Named(name: "a", n: 1), 1)
    m.add(Named(name: "b", n: 1), 2)
    try expect_true(m.get(Named(name: "b", n: 1)).get(0) == 2)
    try expect_true(m.get(Named(name: "c", n: 1)).get(0) == 0)

test "user equal and hash keys":
    var m = Map[Folded, Int]()
    m.add(Folded(n: 1), 1)
    m.add(Folded(n: 2), 2)
    try expect_true(m.length() == 1)
    try expect_true(m.get(Folded(n: 9)).get(0) == 2)
