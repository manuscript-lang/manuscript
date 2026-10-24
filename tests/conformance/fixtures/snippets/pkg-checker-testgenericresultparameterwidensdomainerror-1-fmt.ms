# conform: tags=control-flow,formatter,generics,interfaces,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:89 TestGenericResultParameterWidensDomainError
type Failure:
    code: Int

impl Error for Failure:
    def message() -> String: "failure"

def failing() -> Result[Int, Failure]: error(Failure(code: 1))

def count[T](r: Result[T, Error]) -> Int: 1

def use() -> Int: count(r: failing())
