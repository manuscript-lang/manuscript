// conform: tags=closures,faults,formatter,generics,interfaces,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/defaults_test.go:67 TestDefaultCapturesShareFreely
fn run[T](operation: fn() T) T:
    return operation()

interface Read:
    fn get() Int

fn call(view: Read) Unit:
    callback := fn(value: Int = view.get()) Int:
        return value
    task := fn() Int:
        return callback()
    _result := run(task)
