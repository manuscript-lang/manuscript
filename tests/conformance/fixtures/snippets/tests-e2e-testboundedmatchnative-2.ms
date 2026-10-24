# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=tests/e2e/match_bounds_test.go:61 TestBoundedMatchNative
def probe() -> Int:
    let shapes = [Shape.Circle(2)]
    return area(shapes.get(2))

export def main() -> Int:
    return probe()
