# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:179 TestResultArgumentInferenceRejects
fn domain[T](r: Result[T, E2]) Unit: return

fn first() Unit: domain(f())
