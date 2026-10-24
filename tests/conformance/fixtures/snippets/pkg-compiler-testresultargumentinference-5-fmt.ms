# conform: tags=formatter,generics,parser,records,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:73 TestResultArgumentInference
type Holder[T]:
    r: Result[T, Error]

def first() -> Holder[Int]: Holder(f())
