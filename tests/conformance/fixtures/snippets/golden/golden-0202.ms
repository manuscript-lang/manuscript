// conform: tags=diagnostics
// conform: phase=check
fn make[T, U = Int]() T?: none
fn use() Unit:
    x := make()
