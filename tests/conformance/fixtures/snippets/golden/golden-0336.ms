// conform: tags=diagnostics
// conform: phase=check
type Request:
    callback: fn() Int
fn f(text: String) Result[Request, JsonError]:
    return parse[Request](text)
