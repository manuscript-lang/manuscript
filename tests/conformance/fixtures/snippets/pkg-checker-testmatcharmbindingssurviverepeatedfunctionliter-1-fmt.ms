# conform: tags=closures,formatter,generics,match,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/optional_test.go:34 TestMatchArmBindingsSurviveRepeatedFunctionLiteralChecks
def call[T](operation: Callable[[], T]) -> T:
    return operation()

def get() -> Result[Int, Error]: return ok(value: 1)

def note() -> Unit: return ()

def run() -> Unit:
    call(
        operation: lambda () -> Int:
            match get():
                case ok(_n): note()
                case error(_e): note()

            return 0
    )
