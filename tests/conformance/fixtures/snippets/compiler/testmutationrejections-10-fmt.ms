// conform: tags=formatter,mutation,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/mutation_test.go:31 TestMutationRejections
fn f() Void {
	var value = "a"
	value -= "b"
}
