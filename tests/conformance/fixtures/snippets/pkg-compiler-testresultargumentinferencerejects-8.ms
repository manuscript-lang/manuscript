# conform: tags=control-flow,diagnostics,generics,interfaces,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:194 TestResultArgumentInferenceRejects
interface Read:
    def get() -> Int

impl Read for E1:
    def get() -> Int: self.code

def read[T](r: Result[T, Read]) -> Unit: return

def first() -> Unit: read(f())
