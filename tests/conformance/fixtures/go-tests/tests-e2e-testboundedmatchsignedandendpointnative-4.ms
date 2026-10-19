# conform: tags=control-flow,diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=tests/e2e/match_bounds_test.go:171 TestBoundedMatchSignedAndEndpointNative
export fn main() Int:
    let shapes = [Shape.Circle(2)]
    if area(shapes.get(2, Shape.Tri(7))) != 7: return 1
    return 0
