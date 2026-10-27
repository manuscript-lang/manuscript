# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "switch"
# expect-mir: "closure.new"

from "@std/core.ms" import TextError

type Shape:
    case Circle(radius: Int)
    case Dot

def area(s: Shape) -> Int:
    return match s:
        case Shape.Circle(r): r * r
        case _: 0

def first(xs: List[Int]) -> Result[Int, TextError]:
    let n = try parse(xs.length())
    return ok(n)

def parse(n: Int) -> Result[Int, TextError]:
    if n > 0:
        return ok(n)
    return error(TextError(text: "empty"))

export def main() -> Int:
    let doubled = [1, 2, 3].map(lambda (x) -> Int: x * 2)
    return area(Shape.Circle(doubled.length()))
