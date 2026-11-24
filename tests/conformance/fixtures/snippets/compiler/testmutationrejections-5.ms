// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:26 TestMutationRejections
fn f(value Val) Void {
	value.get = 1
}
