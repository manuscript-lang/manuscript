// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:31 TestMutationRejections
fn f() Void {
	var value = "a"
	value -= "b"
}
// expect-error: MS3000 6:11 arithmetic requires numeric operands
