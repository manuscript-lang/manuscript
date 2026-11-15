// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
    T
    none
fn f(value: Int?) Void: return
fn call() Void: f(4)
