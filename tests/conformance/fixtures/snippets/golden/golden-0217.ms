// conform: tags=diagnostics
// conform: phase=check
fn run[T](operation: fn() T) T:
    return operation()
fn f(value: Int = 1) Int:
    return value
fn call() Int:
    return run(f)
