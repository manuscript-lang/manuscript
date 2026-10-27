from "@std/core.ms" import Iterator
from "@std/io.ms" import stdout
from "@std/test.ms" import expect_equal

# A point in the plane.
type Point:
    x: Int
    y: Int = 0

type Shape:
    case Circle(radius: Int)
    case Square(side: Int)
    case Empty

interface Named:
    def label() -> String

impl Point:
    def norm() -> Int:
        return self.x * self.x + self.y * self.y

impl Named for Point:
    def label() -> String:
        return "point"

type Counter:
    n: Int

impl Iterator[Int] for Counter:
    var def next() -> Optional[Int]:
        if self.n == 0: return none

        self.n -= 1
        return some(self.n)

def add(a: Int, b: Int) -> Int:
    let total = a + b
    return total

def area(shape: Shape) -> Int:
    match shape:
        case Circle(r):
            return r * r * 3
        case Square(s):
            return s * s
        case _:
            return 0

def describe(p: Point) -> String:
    let n = p.norm()
    return f"norm is {n} at {p.x}"

export def main() -> Int:
    let _p = Point(x: 1, y: 2)
    let values = [1, 2, 3]
    for v in values:
        let _ = say(f"{v}")
    for tick in Counter(n: 2):
        let _ = say(f"{tick}")

    let result = add(1, 2)
    return result

def say(text: String) -> Result[Unit, Error]:
    try stdout().write(f"{text}\n")
    return stdout().flush()

test "addition":
    try expect_equal(add(1, 2), 3)
