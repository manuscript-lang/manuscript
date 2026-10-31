# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn source(_0: Int) Int: _0

fn apply[T](callback: fn(String) T) Unit: return

fn exercise() Unit: apply(source)
