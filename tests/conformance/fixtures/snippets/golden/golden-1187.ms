// conform: tags=diagnostics
// conform: phase=check
fn work(value: Int?) Result[Int, Error]:
    return ok(value: value.get())
