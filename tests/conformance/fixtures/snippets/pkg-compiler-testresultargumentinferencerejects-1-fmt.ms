# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:174 TestResultArgumentInferenceRejects
fn bounded[T: Equal](r: Result[T, Error]) Unit: return
fn first(r: Result[Error, E1]) Unit: bounded(r)
