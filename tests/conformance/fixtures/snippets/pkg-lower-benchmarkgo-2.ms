# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/lower/performance_test.go:33 BenchmarkGo
fn work(a: Int, b: Int) Int: return (a + b) * (a - b)
