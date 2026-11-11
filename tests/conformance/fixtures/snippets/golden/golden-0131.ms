// conform: tags=diagnostics
// conform: phase=check
fn p() Result[Int, Error]:
    return ok(1)
fn f(x: Int?) Result[Unit, Error]:
    match x:
        n:
            p()?
            return ok(unit)
        none: return ok(unit)
