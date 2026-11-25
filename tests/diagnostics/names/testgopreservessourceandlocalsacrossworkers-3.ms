// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/gen_test.go:29 TestGoPreservesSourceAndLocalsAcrossWorkers
fn chain() Int => return step15(1)
// expect-error: MS2001 4:26 unknown binding step15; declare it with 'step15 := ...' before use, define 'fn step15(...) T { ... }', or import it from a module
