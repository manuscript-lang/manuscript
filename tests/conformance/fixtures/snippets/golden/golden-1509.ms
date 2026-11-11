// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    shapes := [Shape.Square(3037000499), Shape.Square(-3037000499), Shape.Circle(-3037000499)]
    if area(shapes.get(0)) != 9223372030926249001: return 1
    if area(shapes.get(1)) != 9223372030926249001: return 2
    if area(shapes.get(2)) != -9111001497: return 3
    return 0
