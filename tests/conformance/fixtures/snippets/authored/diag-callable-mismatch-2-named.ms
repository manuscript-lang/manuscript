# conform: tags=diagnostics,closures,types,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn source(value: Int) Int: value

fn exercise() Unit:
    let callback: fn(String) Int = source
