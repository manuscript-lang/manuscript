# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/performance_test.go:33 BenchmarkGo
def work(a: Int, b: Int) -> Int: return (a + b) * (a - b)
