# conform: tags=diagnostics,closures,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn source(_0: Int) Int: _0

fn exercise() Unit:
    let callback: fn(Int?) Int = source
