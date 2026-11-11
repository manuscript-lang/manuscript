// conform: tags=diagnostics
// conform: phase=check
enum Shape:
    Circle(r: Int)
    Square(s: Int)
    Tri(b: Int)
fn area(s: Shape) Int:
    var out = 0
    match s:
        Circle(r):
            out = r * 3
        Square(side):
            out = side * side
        Tri(base):
            out = base
    return out
