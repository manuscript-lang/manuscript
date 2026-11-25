// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:27 TestMutationRejections
fn f() Void {
	value := Val(val: 0)
	value = Val(val: 1)
}
// expect-error: MS2001 5:14 unknown binding Val; declare it with 'Val := ...' before use, define 'fn Val(...) T { ... }', or import it from a module
// expect-error: MS3060 6:5 cannot assign immutable binding value; declare it with 'var value = ...' instead of 'value := ...'
// expect-fix: 5:5-5:13 "var value ="
// expect-error: MS2001 6:13 unknown binding Val; declare it with 'Val := ...' before use, define 'fn Val(...) T { ... }', or import it from a module
