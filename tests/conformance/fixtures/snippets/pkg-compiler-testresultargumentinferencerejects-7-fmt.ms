# conform: tags=closures,formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:192 TestResultArgumentInferenceRejects
fn callback[T](r: Result[fn(value: T) Int, Error]) Unit: return
fn first(r: Result[fn(item: Int) Int, E1]) Unit: callback(r)
