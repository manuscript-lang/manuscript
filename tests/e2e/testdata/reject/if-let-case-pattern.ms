type Shape:
    case Circle(radius: Int)
    case Square

fn size(shape: Shape) Int:
    if let Circle(radius) = shape: return radius
    return 0

export fn main() Int:
    return size(Square)
