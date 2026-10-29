# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:90 TestExpectedResultGenericInferenceRejects
fn first() Unit:
    let callback: fn(Int) Int = from_callback(fn: fn(value: Int = 4): value)
    callback()
