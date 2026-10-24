# conform: tags=formatter,generics,lists,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:185 TestResultArgumentInferenceRejects
def values[T](r: List[Result[T, Error]]) -> Unit: return

def first() -> Unit: values([f()])
