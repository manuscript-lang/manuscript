# conform: tags=diagnostics,match,alternatives,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
type S:
    case A
    case B(x: Int)
def f(s: S) -> Int:
    match s:
        case A:
            return 1
export def main() -> Int:
    return 0
