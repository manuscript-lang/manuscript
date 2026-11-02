# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn source(value: Int) Int: value

fn apply[T](callback: fn(String) T) Unit: return

fn exercise() Unit: apply(source)
