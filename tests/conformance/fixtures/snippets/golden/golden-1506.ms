// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    shapes := [Shape.Circle(2)]
    var sum = 9223372036854775807
    var i = 0
    while i < 2:
        sum += area(shapes.get(0))
        i += 1
    return sum
