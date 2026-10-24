# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/contextual_generics_test.go:93 TestExpectedResultGenericInferenceRejects
def required(value: Int) -> Int: value

def first() -> Unit:
    var callback: Callable[[Int], Int] = from_callback(lambda: lambda (value: Int = 4): value)
    callback = required
    callback()
