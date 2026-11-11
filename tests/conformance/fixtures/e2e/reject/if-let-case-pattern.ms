// conform: tags=testing,tier-core
// conform: phase=check
enum Shape:
    Circle(radius: Int)
    Square

fn size(shape: Shape) Int:
    if let Circle(radius) = shape: return radius
    return 0

export fn main() Int:
    return size(Square)
