# conform: tags=closures,diagnostics,generics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/optional_test.go:34 TestMatchArmBindingsSurviveRepeatedFunctionLiteralChecks
def call[T](operation: Callable[[], T]) -> T:
    return operation()

def get() -> Result[Int, Error]: return ok(value: 1)

def note() -> Unit: return ()

def run() -> Unit:
    call(
        operation: lambda () -> Int:
            match get():
                case ok(n): note()
                case error(e): note()

            return 0
    )
