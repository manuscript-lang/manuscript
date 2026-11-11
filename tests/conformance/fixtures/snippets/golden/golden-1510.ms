// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    shapes := [Shape.Circle(2)]
    if area(shapes.get(2, Shape.Tri(7))) != 7: return 1
    return 0
