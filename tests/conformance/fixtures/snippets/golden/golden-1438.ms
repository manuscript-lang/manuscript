// conform: tags=diagnostics
// conform: phase=check
fn add(a: Int, b: Int) Int:
    sum := a + b
    return sum

export fn main() Int:
    total := add(a: 1, b: 2)
    return total - 3
