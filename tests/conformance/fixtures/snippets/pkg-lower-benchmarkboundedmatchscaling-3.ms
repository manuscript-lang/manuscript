# conform: tags=faults,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:355 BenchmarkBoundedMatchScaling
    return out
fn probe%d() Int:
    let shapes = [Shape%d.C0(1)]
    return area%d(shapes.get(0))
