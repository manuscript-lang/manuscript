# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:38 TestExpectedResultGenericInference
def first() -> Unit:
    let result: Result[Int, TextError] = fail("empty")
