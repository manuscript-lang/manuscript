# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:90 TestExpectedResultGenericInferenceRejects
def first() -> Unit:
    let callback: Callable[[Int], Int] = from_callback(
        lambda: lambda (value: Int = 4): value
    )
    callback()
