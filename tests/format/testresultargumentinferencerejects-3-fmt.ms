// conform: tags=formatter,generics,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:181 TestResultArgumentInferenceRejects
fn same[T, E](first T!E, second T!E) Void => return

fn first() Void => same(first: f(), second: other())
// expect-format: rewritten
// expect-formatted: fn same[T, E](first, second T!E) Void => return
// expect-formatted:
// expect-formatted: fn first() Void => same(first: f(), second: other())
