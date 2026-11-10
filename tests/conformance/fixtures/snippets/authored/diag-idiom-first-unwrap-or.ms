// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int:
    a := [1].first().unwrap_or(0)
    return 0
