# conform: tags=aliasing,closures,formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:98 TestExpectedResultGenericInferenceRejects
fn first() Unit:
    let value: fn(String) Int!TextError = fail
