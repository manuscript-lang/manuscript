// conform: tags=control-flow,diagnostics,formatter,generics,interfaces,records,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/checker/contextual_inference_test.go:12 TestExpectedResultKeepsConcreteSpecialization
fn fail_cause[T, E](move cause E) T!E => error(cause)

fn first() Int! => fail_cause(Error("empty"))
// expect-exit: 0
