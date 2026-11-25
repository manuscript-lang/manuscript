// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:28 TestMutationRejections
fn f(value Val) Void {
	value = Val(val: 1)
}
