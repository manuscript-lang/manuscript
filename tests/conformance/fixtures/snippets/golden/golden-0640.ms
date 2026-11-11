// conform: tags=diagnostics
// conform: phase=check
fn wrong(value: Result[Int, String]) Bool:
    return value.is_some()
