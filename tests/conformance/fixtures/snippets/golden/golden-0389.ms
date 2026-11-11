// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int?) Int: return value.get()
fn call() Int: return f(4)
