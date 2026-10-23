# conform: tags=closures,diagnostics,faults,generics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:67 TestDefaultCapturesShareFreely
fn run[T](operation: fn() T) T:
    return operation()

interface Read:
    fn get() Int

fn call(view: Read) Unit:
    let callback = fn(value: Int = view.get()) Int:
        return value
    let task = fn() Int:
        return callback()
    let result = run(task)
