# conform: tags=parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:26 TestReturnOnlyTypeParameterContext
let result: Result[Int, TextError] = fail("empty")
    return result
