import {expect_equal, expect_false, expect_not_equal, expect_true, fail} from "@std/testing.ms"

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

fn area(shape: Sized) -> Int: shape.width * shape.height

fn shifted(point: Point, by: Int) -> Point:
    return Point(x: point.x + by, y: point.y + by)

test "struct records read write compare format and clone":
    let a = Point(x: 1, y: 2)
    let b = Point(y: 2, x: 1)
    a | try expect_equal(expected: b)
    b.x = 5
    a | try expect_not_equal(expected: b)
    (a.x == 1 and b.x == 5 and shifted(a, by: 3).y == 5) | try expect_true
    let copy = a.clone()
    copy.y = 9
    (a.y == 2 and copy.y == 9) | try expect_true
    if "{a}" != "Point(x: 1, y: 2)": return fail(message: "format changed: {a}")

test "struct records with mixed field types":
    let shape = Shape(
        name: "disc",
        weight: 1.5,
        solid: true,
        corner: Point(x: 0, y: 0),
        tags: ["a"]
    )
    shape.weight = shape.weight * 2.0
    shape.name = "{shape.name}!"
    shape.corner.x = 4
    shape.tags.append("b")
    (
        not (
            shape.weight == 3.0
            and shape.name == "disc!"
            and shape.solid
            and shape.corner.x == 4
            and shape.tags.length() == 2
        )
    ) | try expect_false

test "struct records as keys and defaults":
    let set: Set[Point] = Set[Point]()
    set.add(Point(x: 1, y: 1))
    set.add(Point(x: 1, y: 1))
    set.add(Point(x: 2, y: 1))
    set.length() | try expect_equal(expected: 2)
    let sized = Sized(width: 3)
    (area(sized) != 6 or area(Sized(width: 3, height: 5)) != 15) | try expect_false
