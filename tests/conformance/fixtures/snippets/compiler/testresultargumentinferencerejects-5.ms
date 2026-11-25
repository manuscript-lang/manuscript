// conform: tags=diagnostics,formatter,generics,optional,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:188 TestResultArgumentInferenceRejects
fn twice[T](r T!??) Void => return

fn first() Void => twice(f())
// expect-error: MS2001 6:26 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
