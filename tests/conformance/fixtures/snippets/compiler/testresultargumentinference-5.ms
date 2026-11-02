# conform: tags=diagnostics,generics,records,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:73 TestResultArgumentInference
type Holder[T]:
    r: T!

fn first() Holder[Int]: Holder(f())
