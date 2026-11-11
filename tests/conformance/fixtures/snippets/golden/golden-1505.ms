// conform: tags=diagnostics
// conform: phase=check
fn fail() Int:
    return 1 / 0
export fn main() Int:
    shapes := [Shape.Circle(2)]
    return area(shapes.get(fail() * 0))
