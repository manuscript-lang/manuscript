# conform: tags=diagnostics,generics,try-result,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn f() Result[Int, String]: ok(1)

export fn main() Int: 0
