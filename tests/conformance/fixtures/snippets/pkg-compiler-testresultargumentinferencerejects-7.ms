# conform: tags=closures,diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:192 TestResultArgumentInferenceRejects
def callback[T](r: Result[Callable[[T], Int], Error]) -> Unit: return

def first(r: Result[Callable[[Int], Int], E1]) -> Unit: callback(r)
