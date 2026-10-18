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

fn area(shape: Sized) Int: shape.width * shape.height

fn shifted(point: Point, by: Int) Point:
    return Point(point.x + by, point.y + by)

test "struct records read write compare format and clone":
    let a = Point(1, 2)
    let b = Point(y: 2, x: 1)
    if not (a == b):
        return panic("equal fields must compare equal")

    b.x = 5
    if a == b:
        return panic("mutated record still equal")
    if not (a.x == 1 and b.x == 5 and shifted(a, 3).y == 5):
        return panic("field read or write failed")

    let copy = a.clone()
    copy.y = 9
    if not (a.y == 2 and copy.y == 9):
        return panic("clone shares storage")
    if "{a}" != "Point(x: 1, y: 2)":
        return panic("format changed: {a}")

test "struct records with mixed field types":
    let shape = Shape("disc", 1.5, solid: true, corner: Point(0, 0), tags: ["a"])
    shape.weight *= 2.0
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
        return panic("mixed field access failed")

test "struct records as keys and defaults":
    let set: Set[Point] = Set[Point]()
    set.add(Point(1, 1))
    set.add(Point(1, 1))
    set.add(Point(2, 1))
    if set.length() != 2:
        return panic("record keys must hash structurally")

    let sized = Sized(3)
    if area(sized) != 6 or area(Sized(3, 5)) != 15:
        return panic("defaulted record failed")
