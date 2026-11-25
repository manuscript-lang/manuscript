// conform: tags=diagnostics,closures,generics,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(value String) Int => value.length()

fn apply[T](callback fn(T) Int, value T) Int => callback(value)

fn exercise() Int => apply(source, 3)
// expect-error: MS3001 8:36 expected String, found Int (in argument 'value' of apply); Int does not convert to String implicitly; interpolate it into text, e.g. f"{value}"
// expect-fix: 8:36-8:37 "\"3\""
