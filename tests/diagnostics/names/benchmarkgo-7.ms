// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/performance_test.go:60 BenchmarkGo
fn work() Int => return step % d(1)
// expect-error: MS2001 4:25 unknown binding step; declare it with 'step := ...' before use, define 'fn step(...) T { ... }', or import it from a module
// expect-error: MS2001 4:32 unknown binding d; declare it with 'd := ...' before use, define 'fn d(...) T { ... }', or import it from a module
