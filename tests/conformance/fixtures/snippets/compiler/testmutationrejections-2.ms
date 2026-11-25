// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:23 TestMutationRejections
fn f(value Val) Void {
	value.val = true
}
// expect-error: MS2001 4:12 unknown type Val; declare it with 'type Val:' / 'enum Val:' / 'interface Val:', declare it as a type parameter, or import it
// expect-error: MS3000 5:11 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
