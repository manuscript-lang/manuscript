// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:27 TestMutationRejections
fn f() Void {
	value := Val(val: 0)
	value = Val(val: 1)
}
