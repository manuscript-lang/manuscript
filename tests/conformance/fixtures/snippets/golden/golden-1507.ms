// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    shapes := [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
    if area(shapes.get(0)) != -10: return 1
    if area(shapes.get(1)) != 6: return 2
    if area(shapes.get(2)) != -1: return 3
    if area(shapes.get(-1)) != -1: return 4
    return 0
