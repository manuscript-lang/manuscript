# conform: tags=closures,diagnostics,faults,generics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:67 TestDefaultCapturesShareFreely
def run[T](operation: Callable[[], T]) -> T:
    return operation()

interface Read:
    def get() -> Int

def call(view: Read) -> Unit:
    let callback = lambda (value: Int = view.get()) -> Int:
        return value
    let task = lambda () -> Int:
        return callback()
    let _result = run(task)
