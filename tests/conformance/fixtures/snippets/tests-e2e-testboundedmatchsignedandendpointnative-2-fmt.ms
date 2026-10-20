# conform: tags=control-flow,faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/match_bounds_test.go:158 TestBoundedMatchSignedAndEndpointNative
export fn main() Int:
    let shapes = [Shape.Circle(-3), Shape.Square(4), Shape.Tri(-1)]
    if area(shapes.get(0)) != 4: return 1
    if area(shapes.get(1)) != -8: return 2
    return 0
