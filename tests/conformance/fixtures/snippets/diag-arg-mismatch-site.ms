# conform: tags=diagnostics,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def f(a: Int) -> Int:
    return a
export def main() -> Int:
    return f("s")
