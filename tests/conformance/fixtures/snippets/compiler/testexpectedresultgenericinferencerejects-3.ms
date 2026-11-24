// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/contextual_generics_test.go:90 TestExpectedResultGenericInferenceRejects
fn first() Void:
    callback fn(Int) Int := from_callback(() => fn(value Int = 4) => value)
    callback()
