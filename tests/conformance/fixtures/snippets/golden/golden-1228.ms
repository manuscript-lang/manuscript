// conform: tags=diagnostics
// conform: phase=check
fn work(a: Int) Int:
    b := a + 1
    c := = 3
    return b

export fn main() Int:
    return work(2)
