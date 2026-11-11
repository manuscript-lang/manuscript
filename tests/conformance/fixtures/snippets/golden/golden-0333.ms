// conform: tags=diagnostics
// conform: phase=check
type Request:
    model: String
fn f(text: String) Result[Request, JsonError]:
    request := parse[Request](text)?
    return ok(request)
