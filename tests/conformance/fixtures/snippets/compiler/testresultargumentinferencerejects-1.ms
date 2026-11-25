// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:174 TestResultArgumentInferenceRejects
fn bounded[T Equal](r T!) Void => return

fn first(r Error!E1) Void => bounded(r)
// expect-error: MS2001 6:18 unknown type E1; declare it with 'type E1:' / 'enum E1:' / 'interface E1:', declare it as a type parameter, or import it
