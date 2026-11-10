// conform: tags=diagnostics,match,alternatives,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
enum S:
    A
    B(x: Int)

fn f(s: S) Int:
    match s:
        A:
            return 1

fn main() Unit:
    return
