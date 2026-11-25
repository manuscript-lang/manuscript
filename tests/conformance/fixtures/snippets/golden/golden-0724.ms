// conform: tags=diagnostics
// conform: phase=check
fn both[T, E Error](cause E, r Result[T, E]) Void => return

fn first(cause Error) Void => both[Int, Error](cause: cause, r: f())
