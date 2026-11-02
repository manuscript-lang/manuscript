# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn source(value: Int) String: "text"

fn apply[T](callback: fn(T) Int) Unit: return

fn exercise() Unit: apply(source)
