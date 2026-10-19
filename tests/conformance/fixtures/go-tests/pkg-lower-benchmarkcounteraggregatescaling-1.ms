# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/lower/int_bounds_test.go:244 BenchmarkCounterAggregateScaling
fn probe() Int:
    var sum = 0
    let unrelated = 7
