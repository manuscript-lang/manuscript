// conform: tags=diagnostics
// conform: phase=check
fn unknown(s: Shape) Int: return area(s)
export fn main() Int:
    shapes := [Shape.Circle(2)]
    good := area(shapes.get(0))
    return unknown(Shape.Square(9223372036854775807))
