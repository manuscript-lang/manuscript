# conform: tags=formatter,generics,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:188 TestResultArgumentInferenceRejects
def twice[T](r: Optional[Optional[Result[T, Error]]]) -> Unit: return

def first() -> Unit: twice(f())
