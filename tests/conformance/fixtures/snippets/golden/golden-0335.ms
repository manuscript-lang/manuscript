// conform: tags=diagnostics
// conform: phase=check
fn f[T](text: String) Result[T, JsonError]:
    return parse[T](text)
