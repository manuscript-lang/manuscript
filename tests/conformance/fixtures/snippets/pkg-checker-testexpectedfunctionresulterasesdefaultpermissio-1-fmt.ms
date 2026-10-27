# conform: tags=closures,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:46 TestExpectedFunctionResultErasesDefaultPermissions
def from_callback[T](factory: Callable[[], T]) -> T: factory()

def first() -> Unit:
    let _callback: Callable[[Int], Int] = from_callback(
        lambda: lambda (value: Int = 4): value
    )
