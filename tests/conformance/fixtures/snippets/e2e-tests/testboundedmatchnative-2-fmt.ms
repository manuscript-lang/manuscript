// conform: tags=faults,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/match_bounds_test.go:61 TestBoundedMatchNative
fn probe() Int:
    shapes := [Shape.Circle(2)]
    return area(shapes.get(2))

export fn main() Int:
    return probe()
