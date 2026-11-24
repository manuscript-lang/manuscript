// conform: tags=diagnostics,tier-core
// conform: phase=check
fn apply(f fn(Int) Int, x Int) Int:
    return f(x)

export fn main() Int:
    print(apply(fn a, b: a + b, 1))
    return 0
