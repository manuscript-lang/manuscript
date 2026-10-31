# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:190 TestResultArgumentInferenceRejects
fn nested[T](r: T!!) Unit: return

fn first(r: Int!E1!E2) Unit: nested(r)
