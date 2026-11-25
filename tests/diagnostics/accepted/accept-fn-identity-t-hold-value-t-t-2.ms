// conform: tags=diagnostics
// conform: phase=check
fn identity[T](hold value T) &T => value

fn use() Void { ... }
// expect-exit: 0
