# conform: tags=closures,faults,formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
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
    let result = run(task)
