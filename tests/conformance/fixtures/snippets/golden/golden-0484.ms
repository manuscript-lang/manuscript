// conform: tags=diagnostics
// conform: phase=check
fn failed[T]() Result[T, Failure]: error(Failure("empty"))
fn first() Result[Int, Error]: failed()