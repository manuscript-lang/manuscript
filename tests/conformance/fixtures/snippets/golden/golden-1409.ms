// conform: tags=diagnostics
// conform: phase=check
fn depth(n: Int) Int:
    return 1 + depth(n + 1)
export fn main() Int:
    return depth(0)
