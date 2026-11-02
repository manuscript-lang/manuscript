# conform: tags=diagnostics,generics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:56 TestExpectedResultGenericInference
fn failed[T]() T!Failure: error(Failure("empty"))

fn first() Int!: failed()
