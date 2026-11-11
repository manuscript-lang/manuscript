// conform: tags=diagnostics
// conform: phase=check
fn divide(value: Int) Int:
    return 1 / value
fn outer(value: Int) Int:
    return value
export fn main() Int:
    return outer(
        divide(0)
    )
