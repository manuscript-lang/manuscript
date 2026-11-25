// conform: tags=closures,diagnostics,formatter,generics,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:192 TestResultArgumentInferenceRejects
fn callback[T](r (fn(T) Int)!) Void => return

fn first(r (fn(Int) Int)!E1) Void => callback(r)
// expect-error: MS2001 6:26 unknown type E1; declare it with 'type E1:' / 'enum E1:' / 'interface E1:', declare it as a type parameter, or import it
