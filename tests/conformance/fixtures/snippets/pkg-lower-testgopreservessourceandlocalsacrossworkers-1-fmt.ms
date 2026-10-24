# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/gen_test.go:25 TestGoPreservesSourceAndLocalsAcrossWorkers
def step0[T](value: T) -> T: return value
