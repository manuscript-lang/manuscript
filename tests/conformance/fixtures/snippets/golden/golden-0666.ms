// conform: tags=diagnostics
// conform: phase=check
type Set[T]:
    value: T
fn f(values: Set[Int]) Unit:
    values.add(1)
