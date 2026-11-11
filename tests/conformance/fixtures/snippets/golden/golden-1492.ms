// conform: tags=diagnostics
// conform: phase=check
fn prepare() fn() Int:
    invalid := 1 / 0
    return fn() Int: 1
export fn main()