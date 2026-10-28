# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn source(value: String) Int: value.length()

fn apply[T](callback: fn(T) Int, value: T) Int: callback(value)

fn exercise() Int: apply(source, 3)
