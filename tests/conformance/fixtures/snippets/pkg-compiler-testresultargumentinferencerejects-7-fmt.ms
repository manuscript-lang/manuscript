# conform: tags=closures,formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:192 TestResultArgumentInferenceRejects
fn callback[T](r: (fn(T) Int)!) Unit: return

fn first(r: (fn(Int) Int)!E1) Unit: callback(r)
