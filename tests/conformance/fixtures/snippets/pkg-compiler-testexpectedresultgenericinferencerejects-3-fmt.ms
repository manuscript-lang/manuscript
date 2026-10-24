# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:90 TestExpectedResultGenericInferenceRejects
def first() -> Unit:
    let callback: Callable[[Int], Int] = from_callback(
        lambda: lambda (value: Int = 4): value
    )
    callback()
