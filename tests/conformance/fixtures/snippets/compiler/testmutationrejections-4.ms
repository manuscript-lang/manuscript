// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:25 TestMutationRejections
fn f() Void {
	Val.val = 1
}
// expect-error: MS2001 5:5 unknown binding Val; declare it with 'Val := ...' before use, define 'fn Val(...) T { ... }', or import it from a module
// expect-error: MS3000 5:9 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
