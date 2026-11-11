// conform: tags=diagnostics
// conform: phase=check
fn f(text: String) Result[JsonValue, JsonError]:
    return parse(text)
