# conform: tags=control-flow,formatter,generics,interfaces,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:12 TestExpectedResultKeepsConcreteSpecialization
fn fail_cause[T, E](cause: E) T!E: error(cause)

fn first() Int!: fail_cause(Error("empty"))
