// conform: tags=diagnostics,generics,closures,tier-core
// conform: phase=check
// conform: origin=type-checker bug bash
fn compose[A, B, C](f: fn(A) B, g: fn(B) C) fn(A) C:
    return fn x: g(f(x))

fn main() Unit:
    let e = compose(fn x: x + 1, fn y: "{y}")
