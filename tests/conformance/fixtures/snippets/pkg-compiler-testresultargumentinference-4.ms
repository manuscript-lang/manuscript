# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:71 TestResultArgumentInference
fn both[T, E: Error](cause: E, r: Result[T, E]) Unit: return

fn first(cause: Error) Unit: both[Int, Error](cause: cause, r: f())
