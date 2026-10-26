# conform: tags=diagnostics,types,try-result,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def f() -> Result[Int, Error]:
    return 1
export def main() -> Int:
    return 0
