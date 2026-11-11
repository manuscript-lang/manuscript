// conform: tags=diagnostics
// conform: phase=check
fn wrong() Result[String, Error]:
    return Result[Int, JsonError].ok(value: 1)
