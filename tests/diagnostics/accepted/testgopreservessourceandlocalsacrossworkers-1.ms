// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/gen_test.go:25 TestGoPreservesSourceAndLocalsAcrossWorkers
fn step0[T](hold value T) &T => return value
// expect-exit: 0
