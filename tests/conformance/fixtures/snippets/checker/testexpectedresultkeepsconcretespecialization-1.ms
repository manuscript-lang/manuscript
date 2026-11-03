# conform: tags=control-flow,diagnostics,generics,interfaces,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/contextual_inference_test.go:12 TestExpectedResultKeepsConcreteSpecialization
fn fail_cause[T, E](cause: E) T!E: error(cause)

fn first() Int!: fail_cause(Error("empty"))
