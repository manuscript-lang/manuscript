// conform: tags=diagnostics
// conform: phase=check
fn value(i: Int) Int: i
fn fail() Int:
    return 1 / 0
export fn main() Int:
    data := 