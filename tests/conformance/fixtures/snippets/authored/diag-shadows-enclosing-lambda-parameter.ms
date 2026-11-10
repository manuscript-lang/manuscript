// conform: tags=diagnostics,control-flow,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int:
    x := 1
    f := fn x: return x + 1
    return f(x)
