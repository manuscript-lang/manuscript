// conform: tags=diagnostics,generics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:174 TestResultArgumentInferenceRejects
fn bounded[T Equal](r T!) Void: return

fn first(r Error!E1) Void: bounded(r)
