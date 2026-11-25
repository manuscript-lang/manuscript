// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:34 TestMutationRejections
fn f() Void {
	stdout().clone()
}
