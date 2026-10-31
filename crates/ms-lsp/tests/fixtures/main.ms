import Iterator from "@std/core.ms"
import stdout from "@std/io.ms"
import expect_equal from "@std/test.ms"

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

type Counter:
    n: Int

impl Iterator[Int] for Counter:
    var fn next() Int?:
        if self.n == 0: return none

        self.n -= 1
        return self.n

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
    let _p = Point(x: 1, y: 2)
    let values = [1, 2, 3]
    for v in values:
        let _ = say("{v}")
    for tick in Counter(n: 2):
        let _ = say("{tick}")

    let result = add(1, 2)
    return result

fn say(text: String) Result[Unit, Error]:
    try stdout().write("{text}\n")
    return stdout().flush()

test "addition":
    try expect_equal(add(1, 2), 3)
