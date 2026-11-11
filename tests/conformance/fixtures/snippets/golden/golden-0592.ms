// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    shapes := [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
    var sum = 0
    var i = 0
    while i < 321:
        sum += area(shapes.get(i % 3))
        i += 1
    return sum
