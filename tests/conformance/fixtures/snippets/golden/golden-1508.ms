// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    shapes := [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
    if area(shapes.get(0)) != 4: return 1
    if area(shapes.get(1)) != -8: return 2
    return 0
