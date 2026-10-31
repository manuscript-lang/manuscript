# conform: tags=diagnostics,closures,generics,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
fn broken(first: Missing, second: Int) Int: 1

fn apply[T](callback: fn(T, String) Int) Unit: return

fn exercise() Unit:
    apply(broken)
