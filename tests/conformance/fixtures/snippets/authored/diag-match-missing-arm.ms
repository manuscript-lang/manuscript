# conform: tags=diagnostics,match,alternatives,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
type S:
    case A
    case B(x: Int)

fn f(s: S) Int:
    match s:
        A:
            return 1

export fn main() Int:
    return 0
