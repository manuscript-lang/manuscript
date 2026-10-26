# conform: tags=diagnostics,try-result,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def f() -> Result[Int, Error]:
    return ok(1)
export def main() -> Int:
    let x = f().unwrap()
    return 0
