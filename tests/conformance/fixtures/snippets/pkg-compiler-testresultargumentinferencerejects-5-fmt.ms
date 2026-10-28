# conform: tags=formatter,generics,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:188 TestResultArgumentInferenceRejects
fn twice[T](r: Optional[Optional[Result[T, Error]]]) Unit: return

fn first() Unit: twice(f())
