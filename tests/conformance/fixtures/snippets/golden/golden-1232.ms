// conform: tags=diagnostics
// conform: phase=check
fn identity[T](value: T) T: value
fn first() String: identity(1)
fn second() Int: identity(2)
