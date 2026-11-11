// conform: tags=diagnostics
// conform: phase=check
fn run[T](operation: fn() T) T:
    return operation()
interface Read:
    fn get() Int
fn call(view: Read) Unit:
    callback := fn(value: Int = view.get()) Int:
        return value
    task := fn() Int:
        return callback()
    result := run(task)
