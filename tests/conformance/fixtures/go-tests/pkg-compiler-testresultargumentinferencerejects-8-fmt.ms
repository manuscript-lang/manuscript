# conform: tags=control-flow,formatter,generics,interfaces,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:194 TestResultArgumentInferenceRejects
interface Read:
    fn get() Int
impl Read for E1:
    fn get() Int: self.code
fn read[T](r: Result[T, Read]) Unit: return
fn first() Unit: read(f())
