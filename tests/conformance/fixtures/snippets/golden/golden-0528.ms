// conform: tags=diagnostics
// conform: phase=check
fn identity[T](value: T) T: return value
fn effect(value: Int) Int: return value + 1
