# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=tests/e2e/match_bounds_test.go:67 TestBoundedMatchNative
fn unknown(s: Shape) Int: return area(s)

export fn main() Int:
    let shapes = [Shape.Circle(2)]
    let good = area(shapes.get(0))
    return unknown(Shape.Square(9223372036854775807))
