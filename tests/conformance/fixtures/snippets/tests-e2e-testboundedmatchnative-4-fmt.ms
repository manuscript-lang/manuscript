# conform: tags=faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/match_bounds_test.go:73 TestBoundedMatchNative
fn fail() Int:
    return 1 / 0

export fn main() Int:
    let shapes = [Shape.Circle(2)]
    return area(shapes.get(fail() * 0))
