// conform: tags=diagnostics
// conform: phase=check
type Request:
    model: String
fn f(text: String) Result[Request, JsonError]:
    request: Request := parse(text)?
    return ok(request)
