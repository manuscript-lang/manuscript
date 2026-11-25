// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/mutation_test.go:28 TestMutationRejections
fn f(value Val) Void {
	value = Val(val: 1)
}
// expect-error: MS2001 4:12 unknown type Val; declare it with 'type Val:' / 'enum Val:' / 'interface Val:', declare it as a type parameter, or import it
// expect-error: MS3060 5:5 cannot assign immutable binding value; declare it with 'var value = ...' instead of 'value := ...'
// expect-error: MS2001 5:13 unknown binding Val; declare it with 'Val := ...' before use, define 'fn Val(...) T { ... }', or import it from a module
