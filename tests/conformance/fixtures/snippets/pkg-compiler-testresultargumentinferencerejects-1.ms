# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:174 TestResultArgumentInferenceRejects
def bounded[T: Equal](r: Result[T, Error]) -> Unit: return

def first(r: Result[Error, E1]) -> Unit: bounded(r)
