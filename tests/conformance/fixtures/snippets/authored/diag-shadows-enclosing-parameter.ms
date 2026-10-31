# conform: tags=diagnostics,control-flow,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn f(x: Int) Int:
    if x > 0:
        let x = 2
        return x

    return 0

export fn main() Int:
    return f(1)
