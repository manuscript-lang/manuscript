// conform: tags=diagnostics
// conform: phase=check
fn call[T](operation: fn() T) T:
    return operation()
fn get() Result[Int, Error]: return ok(value: 1)
fn note() Unit: return unit
fn run() Unit:
    call(operation: fn() Int:
        match get():
            ok(n): note()
            error(e): note()
        return 0
    )
