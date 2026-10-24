# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:181 TestResultArgumentInferenceRejects
def same[T, E: Error](first: Result[T, E], second: Result[T, E]) -> Unit: return

def first() -> Unit: same(first: f(), second: other())
