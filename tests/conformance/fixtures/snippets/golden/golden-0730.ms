// conform: tags=diagnostics
// conform: phase=check
fn same[T, E Error](first Result[T, E], second Result[T, E]) Void => return
fn first() Void => same(first: f(), second: other())