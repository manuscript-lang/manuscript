# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/performance_test.go:39 BenchmarkLex
fn invalid() Int:
    return [1, 2)
