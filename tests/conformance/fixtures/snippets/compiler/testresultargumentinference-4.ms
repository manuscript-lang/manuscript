// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:71 TestResultArgumentInference
fn both[T, E](cause E, r T!E) Void => return

fn first(cause Error) Void => both[Int, Error](cause: cause, r: f())
// expect-error: MS2001 6:65 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
