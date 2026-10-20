# conform: tags=generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/gen_test.go:27 TestGoPreservesSourceAndLocalsAcrossWorkers
fn step%d[T](value: T) T: return step%d(value)
