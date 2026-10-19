# conform: tags=match,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:351 BenchmarkBoundedMatchScaling
fn area%d(s: Shape%d) Int:
    var out = 0
    match s:
