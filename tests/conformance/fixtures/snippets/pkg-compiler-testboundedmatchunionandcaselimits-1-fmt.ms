# conform: tags=faults,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/match_bounds_test.go:83 TestBoundedMatchUnionAndCaseLimits
fn other() Int:
    let shapes = [Shape.Square(9223372036854775807)]
    return area(shapes.get(0))
