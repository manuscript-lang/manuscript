# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:190 TestResultArgumentInferenceRejects
def nested[T](r: Result[Result[T, Error], Error]) -> Unit: return

def first(r: Result[Result[Int, E1], E2]) -> Unit: nested(r)
