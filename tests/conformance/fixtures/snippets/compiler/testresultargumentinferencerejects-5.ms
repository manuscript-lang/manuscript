// conform: tags=diagnostics,generics,optional,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:188 TestResultArgumentInferenceRejects
fn twice[T](r T!??) Void: return

fn first() Void: twice(f())
