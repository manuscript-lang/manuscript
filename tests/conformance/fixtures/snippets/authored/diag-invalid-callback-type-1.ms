# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn broken(value: Missing) Int: 1

fn apply[T, U](callback: fn(T) U) Unit: return

fn exercise() Unit:
    apply(broken)
