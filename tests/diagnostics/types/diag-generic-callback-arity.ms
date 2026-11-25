// conform: tags=diagnostics,closures,generics,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn source(first Int, second Int) Int => first + second

fn apply[T](callback fn(T) Int, value T) Int => callback(value)

fn exercise() Int => apply(source, 3)
// expect-error: MS3000 8:28 callback mismatch: the function takes 2 parameters but this position expects 1; pass a function with 1 parameter, or wrap it in a closure that supplies the rest
// expect-error: MS3001 8:28 expected fn(Int) Int, found fn(Int, Int) Int (in argument 'callback' of apply)
