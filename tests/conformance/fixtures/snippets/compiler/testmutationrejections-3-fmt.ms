// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/mutation_test.go:24 TestMutationRejections
fn f(value Val) Void {
	value.missing = 1
}
