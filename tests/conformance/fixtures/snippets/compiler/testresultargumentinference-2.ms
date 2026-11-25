// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:53 TestResultArgumentInference
fn bounded[T Equal](r T!) Void => return

fn first() Void => bounded(f())
// expect-error: MS2001 6:28 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
