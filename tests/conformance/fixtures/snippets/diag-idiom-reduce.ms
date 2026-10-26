# conform: tags=diagnostics,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export def main() -> Int:
    let a = [1].reduce(0, lambda (a: Int, b: Int) -> Int: a + b)
    return 0
