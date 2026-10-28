# conform: tags=aliasing,closures,diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:98 TestExpectedResultGenericInferenceRejects
fn first() Unit:
    let value: fn(String) Result[Int, TextError] = fail
