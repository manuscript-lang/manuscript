// conform: tags=alternatives,diagnostics,generics,records,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:76 TestResultArgumentInference
enum Wrapped[T]:
    value(r: T!)

fn first() Wrapped[Int]: Wrapped.value(f())
