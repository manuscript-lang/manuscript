import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Set from "@std/collections.ms"
import Equal from "@std/equality.ms"
import panic from "@std/faults.ms"

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
    if not (a == b):
        return panic(message: "equal fields must compare equal")

    b.x = 5
    if a == b:
        return panic(message: "mutated record still equal")
    if not (
        a.x == 1
        and b.x == 5
        and shifted(a, by: 3).y == 5
    ):
        return panic(message: "field read or write failed")

    let copy = a.clone()
    copy.y = 9
    if not (a.y == 2 and copy.y == 9):
        return panic(message: "clone shares storage")
    if "{a}" != "Point(x: 1, y: 2)":
        return panic(message: "format changed: {a}")

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
    if not (
        shape.weight == 3.0
        and shape.name == "disc!"
        and shape.solid
        and shape.corner.x == 4
        and shape.tags.length() == 2
    ):
        return panic(message: "mixed field access failed")

test "struct records as keys and defaults":
    let set: Set[Point] = Set[Point]()
    set.with_value(Point(x: 1, y: 1))
    set.with_value(Point(x: 1, y: 1))
    set.with_value(Point(x: 2, y: 1))
    if set.length() != 2:
        return panic(message: "record keys must hash structurally")

    let sized = Sized(width: 3)
    if area(sized) != 6 or area(Sized(width: 3, height: 5)) != 15:
        return panic(message: "defaulted record failed")
