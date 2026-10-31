# conform: tags=control-flow,diagnostics,generics,interfaces,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/contextual_inference_test.go:89 TestGenericResultParameterWidensDomainError
type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failure"

fn failing() Int!Failure: error(Failure(code: 1))

fn count[T](r: T!) Int: 1

fn use() Int: count(r: failing())
