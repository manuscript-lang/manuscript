// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/mutation_test.go:26 TestMutationRejections
fn f(value Val) Void {
	value.get = 1
}
