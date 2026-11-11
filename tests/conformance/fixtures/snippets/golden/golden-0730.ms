// conform: tags=diagnostics
// conform: phase=check
fn same[T, E: Error](first: Result[T, E], second: Result[T, E]) Unit: return
fn first() Unit: same(first: f(), second: other())