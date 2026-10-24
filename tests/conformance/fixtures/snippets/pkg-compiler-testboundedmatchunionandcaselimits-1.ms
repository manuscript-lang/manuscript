# conform: tags=diagnostics,faults,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/match_bounds_test.go:83 TestBoundedMatchUnionAndCaseLimits
def other() -> Int:
    let shapes = [Shape.Square(9223372036854775807)]
    return area(shapes.get(0))
