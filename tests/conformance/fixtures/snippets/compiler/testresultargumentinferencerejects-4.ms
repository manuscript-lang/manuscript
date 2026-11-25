// conform: tags=diagnostics,generics,lists,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:185 TestResultArgumentInferenceRejects
fn values[T](r List[T!]) Void => return

fn first() Void => values([f()])
// expect-error: MS2001 6:28 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
