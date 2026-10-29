# conform: tags=diagnostics,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
export fn main() Int:
    let a = "x".startsWith("x")
    return 0
