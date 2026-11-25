// conform: tags=testing,tier-core
// conform: phase=check
enum Shape {
    Circle(radius Int)
    Square
}

fn size(shape Shape) Int {
    if let Circle(radius) = shape { return radius }
    return 0
}

export fn main() Int {
    return size(Square)
}
// expect-error: MS1000 9:8-9:11 'if let' was removed; test an Optional with 'if value != null { ... }', or unwrap a Result with 'if value := result { ... }'
