# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=tests/e2e/match_bounds_test.go:73 TestBoundedMatchNative
def fail() -> Int:
    return 1 / "".byte_length()

export def main() -> Int:
    let shapes = [Shape.Circle(2)]
    return area(shapes.get(fail() * 0))
