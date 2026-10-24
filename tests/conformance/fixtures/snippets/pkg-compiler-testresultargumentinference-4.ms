# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:71 TestResultArgumentInference
def both[T, E: Error](cause: E, r: Result[T, E]) -> Unit: return

def first(cause: Error) -> Unit: both[Int, Error](cause: cause, r: f())
