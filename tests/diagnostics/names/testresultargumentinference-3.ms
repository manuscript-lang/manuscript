// conform: tags=diagnostics,formatter,generics,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:69 TestResultArgumentInference
fn both[T, E](cause E, r T!E) Void => return

fn first(cause Error) Void => both(cause: cause, r: f())
// expect-error: MS2001 6:53 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
