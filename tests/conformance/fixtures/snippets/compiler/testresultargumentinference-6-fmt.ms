# conform: tags=alternatives,formatter,generics,parser,records,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:76 TestResultArgumentInference
type Wrapped[T]:
    case value(r: T!)

fn first() Wrapped[Int]: Wrapped.value(f())
