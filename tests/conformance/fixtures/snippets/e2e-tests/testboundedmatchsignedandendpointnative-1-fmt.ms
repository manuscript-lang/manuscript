# conform: tags=control-flow,faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/match_bounds_test.go:150 TestBoundedMatchSignedAndEndpointNative
export fn main() Int:
    let shapes = [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
    if area(shapes.get(0)) != -10: return 1
    if area(shapes.get(1)) != 6: return 2
    if area(shapes.get(2)) != -1: return 3
    if area(shapes.get(-1)) != -1: return 4

    return 0
