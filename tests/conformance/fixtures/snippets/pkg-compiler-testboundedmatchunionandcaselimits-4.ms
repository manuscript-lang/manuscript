# conform: tags=faults,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/match_bounds_test.go:106 TestBoundedMatchUnionAndCaseLimits
    return out
fn probe() Int:
    let shapes = [Shape.C0(1)]
    return area(shapes.get(0))
