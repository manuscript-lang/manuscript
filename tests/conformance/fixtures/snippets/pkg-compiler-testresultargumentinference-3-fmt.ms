# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:69 TestResultArgumentInference
fn both[T, E: Error](cause: E, r: Result[T, E]) Unit: return

fn first(cause: Error) Unit: both(cause: cause, r: f())
