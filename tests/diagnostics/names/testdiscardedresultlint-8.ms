// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_lint_test.go:22 TestDiscardedResultLint
fn consume(value Int!) Void => void

fn caller() Void {
	consume(operation())
}
// expect-error: MS2001 7:13 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
