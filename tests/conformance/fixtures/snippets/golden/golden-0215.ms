// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int = 1) Int:
    return value
fn forward[T](value: T) T:
    return value
fn call() Int:
    copy := forward(f)
    return copy()
