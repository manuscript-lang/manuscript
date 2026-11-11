// conform: tags=diagnostics
// conform: phase=check
interface Shape:
    fn area() Int
fn f[T](value: T) Shape: value
