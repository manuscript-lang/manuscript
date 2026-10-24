# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=tests/e2e/match_bounds_test.go:176 TestBoundedMatchSignedAndEndpointNative
export def main() -> Int:
    let shapes = [Shape.Square(3037000500)]
    return area(shapes.get(0))
