// conform: tags=diagnostics,closures,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(value: Int) String: "text"

fn exercise() Unit:
    callback: fn(Int) Int = source
