# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:190 TestResultArgumentInferenceRejects
fn nested[T](r: Result[Result[T, Error], Error]) Unit: return
fn first(r: Result[Result[Int, E1], E2]) Unit: nested(r)
