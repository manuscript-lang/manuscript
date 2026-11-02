# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:53 TestResultArgumentInference
fn bounded[T: Equal](r: T!) Unit: return

fn first() Unit: bounded(f())
