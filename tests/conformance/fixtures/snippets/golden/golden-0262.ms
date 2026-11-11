// conform: tags=diagnostics
// conform: phase=check
fn start[T](operation: fn() T) Int:
    return 0
fn work(n: Int) Int:
    return n
fn f() Int:
    return start(work)
