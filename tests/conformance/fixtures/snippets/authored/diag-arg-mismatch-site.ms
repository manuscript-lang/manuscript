# conform: tags=diagnostics,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn f(a: Int) Int:
    return a

export fn main() Int:
    return f("s")
