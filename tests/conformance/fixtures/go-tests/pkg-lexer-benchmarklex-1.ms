# conform: tags=control-flow,faults,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/performance_test.go:15 BenchmarkLex
fn sample%d(value: Int = 3) Int:
    let items = [value, 2, 3]
    if value >= 0:
        return items[0].get(0) + value
    return 0
