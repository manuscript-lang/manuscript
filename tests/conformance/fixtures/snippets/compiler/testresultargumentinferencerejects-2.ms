// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:179 TestResultArgumentInferenceRejects
fn domain[T](r T!E2) Void => return

fn first() Void => domain(f())
// expect-error: MS2001 4:18 unknown type E2; declare it with 'type E2:' / 'enum E2:' / 'interface E2:', declare it as a type parameter, or import it
// expect-error: MS2001 6:27 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
