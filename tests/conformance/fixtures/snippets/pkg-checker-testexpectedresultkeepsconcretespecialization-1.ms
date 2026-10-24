# conform: tags=control-flow,diagnostics,generics,interfaces,records,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/contextual_inference_test.go:12 TestExpectedResultKeepsConcreteSpecialization
type Failure:
    detail: String

impl Error for Failure:
    def message() -> ref String: self.detail

def fail_cause[T, E: Error](cause: E) -> Result[T, E]: error(cause)

def first() -> Result[Int, Error]: fail_cause(Failure("empty"))
