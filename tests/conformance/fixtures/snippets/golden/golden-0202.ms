// conform: tags=diagnostics
// conform: phase=check
fn make[T, U = Int]() T?: null
fn use() Void:
    x := make()
