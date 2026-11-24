// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:179 TestResultArgumentInferenceRejects
fn domain[T](r T!E2) Void: return

fn first() Void: domain(f())
