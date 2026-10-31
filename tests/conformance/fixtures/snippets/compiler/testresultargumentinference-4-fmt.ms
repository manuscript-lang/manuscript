# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:71 TestResultArgumentInference
fn both[T, E: Error](cause: E, r: T!E) Unit: return

fn first(cause: Error) Unit: both[Int, Error](cause: cause, r: f())
