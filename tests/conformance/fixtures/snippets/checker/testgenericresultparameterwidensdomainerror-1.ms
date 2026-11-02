# conform: tags=control-flow,diagnostics,generics,interfaces,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/contextual_inference_test.go:89 TestGenericResultParameterWidensDomainError
fn failing() Int!: error(Error("failure"))

fn count[T](r: T!) Int: 1

fn use() Int: count(r: failing())
