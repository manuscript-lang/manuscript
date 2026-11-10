// conform: tags=strings,interpolation,records,tier-core
// conform: phase=run
// conform: origin=print is a prelude function: no import, any value as text, then a newline
type Point:
    x: Int
    y: Int

fn main() Unit:
    print("hello")
    print(42)
    print(Point(1, 2))
    print([1, 2, 3])

    let name = "ms"
    print("name: {name}")
