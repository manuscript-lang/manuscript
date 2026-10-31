# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:56 TestExpectedResultGenericInference
fn failed[T]() T!Failure: error(Failure("empty"))

fn first() Int!: failed()
