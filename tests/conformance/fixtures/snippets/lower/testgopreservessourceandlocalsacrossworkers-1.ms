// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/lower/gen_test.go:25 TestGoPreservesSourceAndLocalsAcrossWorkers
fn step0[T](hold value T) &T => return value
// expect-exit: 0
