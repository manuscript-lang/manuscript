# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:53 TestResultArgumentInference
def bounded[T: Equal](r: Result[T, Error]) -> Unit: return

def first() -> Unit: bounded(f())
