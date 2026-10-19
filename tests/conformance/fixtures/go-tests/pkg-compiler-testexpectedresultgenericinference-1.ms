# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:38 TestExpectedResultGenericInference
fn first() Unit:
    let result: Result[Int, TextError] = fail("empty")
