# conform: tags=faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/match_bounds_test.go:67 TestBoundedMatchNative
def unknown(s: Shape) -> Int: return area(s)

export def main() -> Int:
    let shapes = [Shape.Circle(2)]
    let good = area(shapes.get(0))
    return unknown(Shape.Square(9223372036854775807))
