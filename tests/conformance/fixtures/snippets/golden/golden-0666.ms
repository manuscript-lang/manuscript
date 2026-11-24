// conform: tags=diagnostics
// conform: phase=check
type Set[T]:
    value T
fn f(values Set[Int]) Void:
    values.add(1)
