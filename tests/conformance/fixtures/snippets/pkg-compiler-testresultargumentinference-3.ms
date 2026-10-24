# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:69 TestResultArgumentInference
def both[T, E: Error](cause: E, r: Result[T, E]) -> Unit: return

def first(cause: Error) -> Unit: both(cause: cause, r: f())
