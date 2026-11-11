// conform: tags=diagnostics
// conform: phase=check
fn add(a: Int, b: Int) Int:
    total := a + b
    return total

export fn main() Int:
    return add(1, 2)
