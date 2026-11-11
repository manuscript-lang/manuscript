// conform: tags=diagnostics
// conform: phase=check
fn first[T](left: T, right: T) T: return left
fn call(left: Int, right: Int) Int: return first(right, left)
