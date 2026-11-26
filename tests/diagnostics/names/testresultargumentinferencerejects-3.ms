// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:181 TestResultArgumentInferenceRejects
fn same[T, E](first T!E, second T!E) Void => return

fn first() Void => same(first: f(), second: other())
// expect-error: MS2001 6:32 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
// expect-error: MS2001 6:45 unknown binding other; declare it with 'other := ...' before use, define 'fn other(...) T { ... }', or import it from a module
