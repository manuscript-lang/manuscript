# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:179 TestResultArgumentInferenceRejects
def domain[T](r: Result[T, E2]) -> Unit: return

def first() -> Unit: domain(f())
