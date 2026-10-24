# conform: tags=formatter,generics,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:56 TestExpectedResultGenericInference
def failed[T]() -> Result[T, Failure]: error(Failure("empty"))

def first() -> Result[Int, Error]: failed()
