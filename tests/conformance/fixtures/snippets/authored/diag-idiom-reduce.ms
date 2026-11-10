// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Unit:
    a := [1].reduce(0, fn(a: Int, b: Int) Int: a + b)
