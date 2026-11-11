// conform: tags=diagnostics
// conform: phase=check
fn f(x: Int?) Result[Unit, Error]:
    match x:
        n:
            g(n)?
            return ok(unit)
        none: return ok(unit)
