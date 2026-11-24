// conform: tags=formatter,generics,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:71 TestResultArgumentInference
fn both[T, E](cause E, r T!E) Void: return

fn first(cause Error) Void: both[Int, Error](cause: cause, r: f())
