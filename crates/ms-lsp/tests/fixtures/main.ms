import stdout from "@std/io.ms"
import {expect_equal} from "@std/testing.ms"

# A point in the plane.
type Point:
    x: Int
    y: Int = 0

type Shape:
    case Circle(radius: Int)
    case Square(side: Int)
    case Empty

interface Named:
    fn label() String

impl Point:
    fn norm() Int:
        return self.x * self.x + self.y * self.y

impl Named for Point:
    fn label() String:
        return "point"

fn add(a: Int, b: Int) Int:
    let total = a + b
    return total

fn area(shape: Shape) Int:
    match shape:
        Circle(r):
            return r * r * 3
        Square(s):
            return s * s
        _:
            return 0

fn describe(p: Point) String:
    let n = p.norm()
    return "norm is {n} at {p.x}"

export fn main() Int:
    let p = Point(x: 1, y: 2)
    let values = [1, 2, 3]
    for v in values:
        say("{v}")
    let result = add(1, 2)
    return result

fn say(text: String) Result[Unit, Error]:
    try stdout().write("{text}\n")
    return stdout().flush()

test "addition":
    try expect_equal(add(1, 2), 3)
