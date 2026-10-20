# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/gen_test.go:29 TestGoPreservesSourceAndLocalsAcrossWorkers
fn chain() Int: return step15(1)
