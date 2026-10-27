# conform: tags=diagnostics,control-flow,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def f(x: Int) -> Int:
    if x > 0:
        let x = 2
        return x
    return 0
export def main() -> Int:
    return f(1)
