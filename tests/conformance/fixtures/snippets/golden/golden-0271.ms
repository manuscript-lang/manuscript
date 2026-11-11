// conform: tags=diagnostics
// conform: phase=check
fn p() Result[Int, Error]:
    return ok(1)
fn f() Int:
    return p() + 1
