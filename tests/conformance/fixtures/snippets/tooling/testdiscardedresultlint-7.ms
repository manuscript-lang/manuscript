// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_lint_test.go:21 TestDiscardedResultLint
fn caller() Int! {
	value := operation()
	return value
}
// expect-error: MS2001 5:14 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
