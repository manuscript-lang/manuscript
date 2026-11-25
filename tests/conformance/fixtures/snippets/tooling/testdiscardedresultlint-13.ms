// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/result_lint_test.go:27 TestDiscardedResultLint
fn caller() Int! => operation()
// expect-error: MS2001 4:21 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
