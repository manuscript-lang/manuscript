// conform: tags=diagnostics
// conform: phase=check
fn p() Result[Int, Error]:
    return ok(1)
fn f(x Int?) Result[Void, Error]:
    match x:
        n:
            p()?
            return ok()
        null => return ok()
