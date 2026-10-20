# conform: tags=control-flow,formatter,generics,interfaces,parser,records,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:12 TestExpectedResultKeepsConcreteSpecialization
type Failure:
    detail: String
impl Error for Failure:
    fn message() String: self.detail
fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)
fn first() Result[Int, Error]: fail_cause(Failure("empty"))
