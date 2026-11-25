// conform: tags=diagnostics,closures,generics,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(_0 Int) Int => _0

fn apply[T](callback fn(String) T) Void => return

fn exercise() Void => apply(source)
// expect-error: MS3080 8:23 cannot infer type argument T for apply; write apply[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
