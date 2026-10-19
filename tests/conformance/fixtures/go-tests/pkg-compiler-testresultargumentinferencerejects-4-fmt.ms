# conform: tags=formatter,generics,lists,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:185 TestResultArgumentInferenceRejects
fn values[T](r: List[Result[T, Error]]) Unit: return
fn first() Unit: values([f()])
