type Point:
    x: Int
    y: Int

fn show(p: Point) String:
    return f"<{p}>"

fn main() Int:
    text := show(Point(x: 1, y: 2))
    if text.length() > 100:
        return 1
    return 0

enum Shape:
    Dot
    Circle(Float)
    Box(Int, Bool)

type Mark:
    name: String
    at: Point
    kind: Shape

fn describe(s: Shape, m: Mark) String:
    return f"{s} and {m}"

fn run() Int:
    s := describe(Box(2, true), Mark(name: "", at: Point(x: 1, y: 2), kind: Dot))
    return s.length()
