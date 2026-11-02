# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "switch"
# expect-mir: "closure.new"

type Shape:
    case Circle(radius: Int)
    case Dot

fn area(s: Shape) Int:
    return match s:
        Shape.Circle(r): r * r
        _: 0

fn first(xs: List[Int]) Result[Int, Error]:
    let n = try parse(xs.length())
    return ok(n)

fn parse(n: Int) Result[Int, Error]:
    if n > 0:
        return ok(n)

    return error(Error(message: "empty"))

export fn main() Int:
    let doubled = [1, 2, 3].map(fn(x) Int: x * 2)
    return area(Shape.Circle(doubled.length()))
