# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:87 TestExpectedResultGenericInferenceRejects
def first() -> Callable[[Int], Int]:
    let callback = lambda (item: Int): item
    return identity(callback)
