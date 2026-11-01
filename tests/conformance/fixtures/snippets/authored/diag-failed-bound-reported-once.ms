# conform: tags=diagnostics,generics,try-result,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn describe[E: Error](cause: E) String: cause.message()

export fn main() Int:
    let _message = describe("missing")
    return 0
