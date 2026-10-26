# conform: tags=diagnostics,generics,try-result,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def f() -> Result[Int, String]: ok(1)
export def main() -> Int: 0
