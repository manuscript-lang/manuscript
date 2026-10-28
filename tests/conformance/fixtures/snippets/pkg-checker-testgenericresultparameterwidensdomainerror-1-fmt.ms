# conform: tags=control-flow,formatter,generics,interfaces,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:89 TestGenericResultParameterWidensDomainError
type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failure"

fn failing() Result[Int, Failure]: error(Failure(code: 1))

fn count[T](r: Result[T, Error]) Int: 1

fn use() Int: count(r: failing())
