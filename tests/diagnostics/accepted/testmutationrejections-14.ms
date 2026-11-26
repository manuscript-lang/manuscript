// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:35 TestMutationRejections
fn f(file File) Void {
	file.clone()
}
// expect-error: MS2001 4:11 unknown type File; declare it with 'type File:' / 'enum File:' / 'interface File:', declare it as a type parameter, or import it
