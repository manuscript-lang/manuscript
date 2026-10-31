# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:90 TestExpectedResultGenericInferenceRejects
fn first() Unit:
    let callback: fn(Int) Int = from_callback(fn: fn(value: Int = 4): value)
    callback()
