// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:35 TestMutationRejections
fn f(file File) Void {
	file.clone()
}
