// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
    T
    none
fn f(value: Int?) Unit: return
fn call() Unit: f(4)
