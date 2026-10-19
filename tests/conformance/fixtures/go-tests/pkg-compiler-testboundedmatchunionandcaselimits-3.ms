# conform: tags=match,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/match_bounds_test.go:102 TestBoundedMatchUnionAndCaseLimits
fn area(s: Shape) Int:
    var out = 0
    match s:
