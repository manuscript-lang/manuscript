# conform: tags=closures,diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/contextual_inference_test.go:46 TestExpectedFunctionResultErasesDefaultPermissions
def from_callback[T](factory: Callable[[], T]) -> T: factory()

def first() -> Unit:
    let callback: Callable[[Int], Int] = from_callback(
        lambda: lambda (value: Int = 4): value
    )
