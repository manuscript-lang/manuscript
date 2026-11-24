// conform: tags=diagnostics,closures,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(_0 Int) String: "text"

fn exercise() Void:
    callback fn(Int) Int := source
