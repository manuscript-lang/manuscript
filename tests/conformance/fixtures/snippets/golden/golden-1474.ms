// conform: tags=diagnostics
// conform: phase=check
fn divide(value: Int = 1 / 0) Int:
    return value
export fn main() Int:
    return divide()
