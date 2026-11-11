// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    shapes := [Shape.Circle(2)]
    return area(shapes.get(2))
export fn main() Int:
    return probe()
