# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:87 TestExpectedResultGenericInferenceRejects
fn first() fn(Int) Int:
    let callback = fn(item: Int): item
    return identity(callback)
