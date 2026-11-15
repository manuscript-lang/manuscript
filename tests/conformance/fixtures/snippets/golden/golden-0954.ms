// conform: tags=diagnostics
// conform: phase=check
fn f(x: Int?) Result[Void, Error]:
    match x:
        n:
            g(n)?
            return ok()
        none: return ok()
