// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:190 TestResultArgumentInferenceRejects
fn nested[T](r T!!) Void => return

fn first(r Int!E1!E2) Void => nested(r)
// expect-error: MS2001 6:16 unknown type E1; declare it with 'type E1:' / 'enum E1:' / 'interface E1:', declare it as a type parameter, or import it
// expect-error: MS2001 6:19 unknown type E2; declare it with 'type E2:' / 'enum E2:' / 'interface E2:', declare it as a type parameter, or import it
