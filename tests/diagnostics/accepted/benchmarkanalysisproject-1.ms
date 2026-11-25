// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/analysis_bench_test.go:26 BenchmarkAnalysisProject
export fn value() Int => return 1
// expect-exit: 0
