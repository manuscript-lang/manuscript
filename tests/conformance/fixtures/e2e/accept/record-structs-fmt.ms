# conform: tags=control-flow,formatter,interpolation,lists,modules,numbers,parser,records,sets,stdlib-testing,strings,testing,tier-core,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/record-structs.ms
from "@std/test.ms" import expect_equal, expect_false, expect_not_equal, fail

type Point:
    x: Int
    y: Int

type Shape:
    name: String
    weight: Float
    solid: Bool
    corner: Point
    tags: List[String]

type Sized:
    width: Int
    height: Int = 2

def area(shape: Sized) -> Int: shape.width * shape.height

def shifted(point: Point, by: Int) -> Point:
    return Point(point.x + by, point.y + by)

test "struct records read write compare format and clone":
    let a = Point(1, 2)
    var b = Point(y: 2, x: 1)
    try expect_equal(a, b)
    b.x = 5
    try expect_not_equal(a, b)
    try expect_false(not (a.x == 1 and b.x == 5 and shifted(a, 3).y == 5))

    var copy = a.clone()
    copy.y = 9
    try expect_false(not (a.y == 2 and copy.y == 9))
    if f"{a}" != "Point(x: 1, y: 2)": return fail(f"format changed: {a}")

test "struct records with mixed field types":
    var shape = Shape("disc", 1.5, solid: True, corner: Point(0, 0), tags: ["a"])
    shape.weight *= 2.0
    shape.name = f"{shape.name}!"
    shape.corner.x = 4
    shape.tags.append("b")
    try expect_false(
        not (
            shape.weight == 3.0
            and shape.name == "disc!"
            and shape.solid
            and shape.corner.x == 4
            and shape.tags.length() == 2
        )
    )

test "struct records as keys and defaults":
    var set: Set[Point] = Set[Point]()
    set.add(Point(1, 1))
    set.add(Point(1, 1))
    set.add(Point(2, 1))
    try expect_equal(set.length(), 2)

    let sized = Sized(3)
    try expect_false(area(sized) != 6 or area(Sized(3, 5)) != 15)
