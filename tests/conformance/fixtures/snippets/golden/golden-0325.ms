// conform: tags=diagnostics
// conform: phase=check
interface Shape:
    fn area() Int
fn f(value: fn() Int) Shape: value
