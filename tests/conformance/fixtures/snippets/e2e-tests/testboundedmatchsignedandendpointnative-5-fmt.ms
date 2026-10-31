# conform: tags=faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/match_bounds_test.go:176 TestBoundedMatchSignedAndEndpointNative
export fn main() Int:
    let shapes = [Shape.Square(3037000500)]
    return area(shapes.get(0))
