# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_argument_inference_test.go:181 TestResultArgumentInferenceRejects
fn same[T, E](first: T!E, second: T!E) Unit: return

fn first() Unit: same(first: f(), second: other())
